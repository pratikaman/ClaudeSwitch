import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var orphans: [OrphanEntry] = []
    @Published var prefs: Prefs = .load()
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var managerTab = 0

    init() {
        if !prefs.terminal.isInstalled, let first = TerminalApp.installed.first {
            prefs.terminal = first
            prefs.save()
        }
        reload()
    }

    // MARK: - Discovery

    func reload() {
        let aliasMap = Discovery.aliases()
        let dirs = Discovery.configDirs(extraPaths: prefs.extraPaths)

        var built: [Profile] = []
        for dir in dirs {
            let ov = prefs.overrides[dir] ?? ProfileOverride()
            if ov.hidden { continue }
            let isDefault = (dir == Discovery.defaultDir)
            var p = Profile(
                configDir: dir,
                isDefault: isDefault,
                name: ov.name ?? Discovery.derivedName(for: dir),
                account: Discovery.account(in: dir),
                credential: nil,
                alias: aliasMap[dir],
                workingDir: ov.workingDir,
                command: ov.command ?? prefs.defaultCommand,
                usage: nil
            )
            p.credential = Keychain.credential(forService: p.keychainService)
            built.append(p)
        }

        built.sort { a, b in
            let oa = prefs.overrides[a.configDir]?.order ?? (a.isDefault ? -1 : 0)
            let ob = prefs.overrides[b.configDir]?.order ?? (b.isDefault ? -1 : 0)
            return (oa, a.name) < (ob, b.name)
        }

        profiles = built
        Launcher.pruneScripts(keeping: built)
        recomputeOrphans()
        Task { await hydrateUsageFromCache() }
    }

    /// Credential entries in the keychain with no matching config dir on disk.
    func recomputeOrphans() {
        let known = Set(profiles.map(\.keychainService))
        // Also treat dirs the user hid as "known" so we don't offer to nuke them.
        let hidden = Set(prefs.overrides.filter(\.value.hidden).keys.map {
            $0 == Discovery.defaultDir ? Keychain.servicePrefix
                                       : "\(Keychain.servicePrefix)-\(sha256Prefix8($0))"
        })
        orphans = Keychain.allClaudeServices()
            .filter { !known.contains($0) && !hidden.contains($0) }
            .map { OrphanEntry(service: $0, credential: Keychain.credential(forService: $0)) }
    }

    // MARK: - Usage

    func hydrateUsageFromCache() async {
        for i in profiles.indices {
            profiles[i].usage = await UsageClient.shared.cached(forService: profiles[i].keychainService)
        }
    }

    func refreshUsage(force: Bool = false) async {
        guard prefs.showUsageInMenu else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Sequential, and paced: the usage endpoint 429s on back-to-back calls,
        // which was enough to blank a second account on every refresh.
        var networkCalls = 0
        for i in profiles.indices where profiles[i].isSignedIn {
            let service = profiles[i].keychainService
            let willHitNetwork = await UsageClient.shared.needsFetch(
                forService: service, ttl: prefs.usageTTLSeconds, force: force)
            if willHitNetwork && networkCalls > 0 {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
            if willHitNetwork { networkCalls += 1 }
            let snap = await UsageClient.shared.usage(forService: service,
                                                      ttl: prefs.usageTTLSeconds,
                                                      force: force)
            if let idx = profiles.firstIndex(where: { $0.keychainService == service }) {
                profiles[idx].usage = snap
            }
        }
    }

    // MARK: - Launching

    func launch(_ profile: Profile) {
        lastError = Launcher.launch(profile, prefs: prefs)
        if lastError == nil {
            prefs.lastUsed[profile.configDir] = Date()
            prefs.save()
        }
    }

    /// The account to reach for right now: signed in, most rate-limit headroom,
    /// ties broken by whichever you used most recently.
    var heroProfile: Profile? {
        let signedIn = profiles.filter(\.isSignedIn)
        guard !signedIn.isEmpty else { return profiles.first }
        // Prefer accounts whose limits we actually know; fall back to the rest.
        let withData = signedIn.filter(\.hasUsageData)
        let candidates = withData.isEmpty ? signedIn : withData
        return candidates.min { a, b in
            if a.headroomScore != b.headroomScore { return a.headroomScore < b.headroomScore }
            let ta = prefs.lastUsed[a.configDir] ?? .distantPast
            let tb = prefs.lastUsed[b.configDir] ?? .distantPast
            return ta > tb
        }
    }

    /// Config dirs signed into the same Anthropic account share one quota.
    /// Worth surfacing — two profiles is not two allowances.
    func quotaSiblings(of profile: Profile) -> [Profile] {
        guard let uuid = profile.account?.accountUuid, !uuid.isEmpty else { return [] }
        return profiles.filter { $0.configDir != profile.configDir && $0.account?.accountUuid == uuid }
    }

    /// Highest weekly usage across signed-in accounts, for the menu bar readout.
    var menuBarPercent: Double? {
        let recent = profiles
            .filter { $0.isSignedIn && $0.weeklyPercent != nil }
            .max { (prefs.lastUsed[$0.configDir] ?? .distantPast) < (prefs.lastUsed[$1.configDir] ?? .distantPast) }
        return recent?.weeklyPercent
    }

    func signIn(_ profile: Profile) {
        lastError = Launcher.signIn(profile, prefs: prefs)
    }

    // MARK: - Profile management

    /// Creates a new config dir and opens the login flow in a terminal.
    func addProfile(name rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        guard !name.isEmpty else { lastError = "name required"; return }

        let dir = NSHomeDirectory() + "/.claude-" + name
        if FileManager.default.fileExists(atPath: dir) {
            lastError = "\(dir.abbreviatingTilde) already exists"
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
            // A stub settings.json makes the dir discoverable before first login.
            try "{}\n".write(toFile: dir + "/settings.json", atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            return
        }

        var ov = prefs.overrides[dir] ?? ProfileOverride()
        ov.name = name
        prefs.overrides[dir] = ov
        prefs.save()
        reload()

        if let fresh = profiles.first(where: { $0.configDir == dir }) {
            // No credentials yet, so run plain `claude` — it starts the login flow.
            lastError = Launcher.launch(fresh, prefs: prefs, overrideCommand: "command claude")
        }
    }

    /// Removes a profile. The directory goes to the Trash, never rm -rf.
    func removeProfile(_ profile: Profile, deleteDirectory: Bool, deleteCredential: Bool) {
        if profile.isDefault {
            lastError = "the default ~/.claude profile can't be removed"
            return
        }
        if deleteCredential { Keychain.delete(service: profile.keychainService) }
        if deleteDirectory {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: profile.configDir),
                                                  resultingItemURL: nil)
            } catch {
                lastError = "could not trash \(profile.shortDir): \(error.localizedDescription)"
            }
            prefs.overrides.removeValue(forKey: profile.configDir)
        } else {
            var ov = prefs.overrides[profile.configDir] ?? ProfileOverride()
            ov.hidden = true
            prefs.overrides[profile.configDir] = ov
        }
        prefs.save()
        reload()
    }

    func deleteOrphan(_ orphan: OrphanEntry) {
        if Keychain.delete(service: orphan.service) {
            orphans.removeAll { $0.service == orphan.service }
        } else {
            lastError = "could not delete \(orphan.service)"
        }
    }

    /// Bulk credential deletion is permanent and unrecoverable — there is no
    /// Trash for the keychain — so it always goes through a confirmation.
    func confirmDeleteAllOrphans() {
        let live = orphans.filter { $0.credential != nil }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(orphans.count) leftover login\(orphans.count == 1 ? "" : "s")?"
        alert.informativeText = live > 0
            ? "\(live) of them still hold a working refresh token. This removes them from your keychain permanently — there is no undo."
            : "This removes them from your keychain permanently — there is no undo."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for o in orphans { Keychain.delete(service: o.service) }
        recomputeOrphans()
    }

    // MARK: - Overrides

    /// Applies an override and refreshes only the affected row.
    ///
    /// This runs on every keystroke in the manager's text fields, so it must not
    /// call reload() — that re-reads every config dir and shells out to
    /// /usr/bin/security once per profile.
    func update(_ profile: Profile, _ mutate: (inout ProfileOverride) -> Void) {
        var ov = prefs.overrides[profile.configDir] ?? ProfileOverride()
        mutate(&ov)
        prefs.overrides[profile.configDir] = ov
        prefs.save()

        guard let i = profiles.firstIndex(where: { $0.configDir == profile.configDir }) else { return }
        if let name = ov.name, !name.isEmpty { profiles[i].name = name }
        else { profiles[i].name = Discovery.derivedName(for: profile.configDir) }
        profiles[i].command = ov.command ?? prefs.defaultCommand
        profiles[i].workingDir = ov.workingDir
    }

    func savePrefs() {
        prefs.save()
        reload()
    }

    // MARK: - Shell aliases

    /// Appends an alias for a profile into a ClaudeSwitch-managed block in ~/.zshrc.
    /// Existing hand-written aliases are left completely alone.
    func writeAlias(for profile: Profile, named alias: String) {
        let rc = NSHomeDirectory() + "/.zshrc"
        let begin = "# >>> claudeswitch aliases >>>"
        let end = "# <<< claudeswitch aliases <<<"

        var text = (try? String(contentsOfFile: rc, encoding: .utf8)) ?? ""

        // Back up before touching the user's shell config.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        try? text.write(toFile: rc + ".claudeswitch-bak-" + stamp, atomically: true, encoding: .utf8)

        let line = profile.isDefault
            ? "alias \(alias)=\(shellQuote(profile.command))"
            : "alias \(alias)=\(shellQuote("CLAUDE_CONFIG_DIR=\(profile.configDir) command \(profile.command)"))"

        if let b = text.range(of: begin), let e = text.range(of: end) {
            var block = String(text[b.upperBound..<e.lowerBound])
            block = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("alias \(alias)=") }
                .joined(separator: "\n")
            let rebuilt = block.trimmingCharacters(in: .newlines) + "\n" + line + "\n"
            text.replaceSubrange(b.upperBound..<e.lowerBound, with: "\n" + rebuilt)
        } else {
            text += "\n\n\(begin)\n\(line)\n\(end)\n"
        }

        do {
            try text.write(toFile: rc, atomically: true, encoding: .utf8)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
