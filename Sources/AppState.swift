import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var orphans: [OrphanEntry] = []
    @Published var prefs: Prefs = Prefs()
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var managerTab = 0
    @Published var providerFilter: AIProvider?
    var visibleProfiles: [Profile] {
        profiles.filter { providerFilter == nil || $0.provider == providerFilter }
    }
    /// Recent resumable conversations, keyed by config dir.
    @Published var sessions: [String: [RecentSession]] = [:]
    @Published var notifyStatus: String = ""
    private var pollTimer: Timer?
    private let isPreview: Bool

    init(previewProfiles: [Profile]? = nil) {
        isPreview = previewProfiles != nil
        if let previewProfiles {
            profiles = previewProfiles
            prefs.notifyEnabled = false
            return
        }
        prefs = .load()
        if !prefs.terminal.isInstalled, let first = TerminalApp.installed.first {
            prefs.terminal = first
            prefs.save()
        }
        reload()
        // Alerts have to run whether or not the menu is ever opened.
        startPolling()
    }

    // MARK: - Discovery

    func reload() {
        guard !isPreview else { return }
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

        for provider in [AIProvider.codex, .grok] {
            let paths = provider == .codex ? prefs.codexPaths : prefs.grokPaths
            for dir in CLIAccountDiscovery.configDirs(extraPaths: paths, provider: provider) {
                let ov = prefs.overrides[provider.profileID(for: dir)] ?? ProfileOverride()
                guard !ov.hidden else { continue }
                let previous = profiles.first { $0.provider == provider && $0.configDir == dir }
                built.append(Profile(configDir: dir, isDefault: dir == provider.defaultDir,
                                     name: ov.name ?? provider.derivedName(for: dir),
                                     account: previous?.account, credential: previous?.credential,
                                     workingDir: ov.workingDir, command: ov.command ?? provider.rawValue,
                                     usage: previous?.usage, provider: provider))
            }
        }

        built.sort { a, b in
            let oa = prefs.overrides[a.id]?.order ?? (a.isDefault ? -1 : 0)
            let ob = prefs.overrides[b.id]?.order ?? (b.isDefault ? -1 : 0)
            return (a.provider.rawValue, oa, a.name) < (b.provider.rawValue, ob, b.name)
        }

        profiles = built
        if prefs.showRecentSessions {
            var found: [String: [RecentSession]] = [:]
            for profile in built where profile.provider == .claude {
                found[profile.configDir] = Sessions.recent(in: profile.configDir, limit: 5)
            }
            sessions = found
        } else {
            sessions = [:]
        }
        Launcher.pruneScripts(keeping: built)
        recomputeOrphans()
        Task { await hydrateUsageFromCache() }
    }

    /// Credential entries in the keychain with no matching config dir on disk.
    func recomputeOrphans() {
        let known = Set(profiles.filter { $0.provider == .claude }.map(\.keychainService))
        // Also treat dirs the user hid as "known" so we don't offer to nuke them.
        let hidden = Set(prefs.overrides.filter { $0.value.hidden && $0.key.hasPrefix("/") }.keys.map {
            $0 == Discovery.defaultDir ? Keychain.servicePrefix
                                       : "\(Keychain.servicePrefix)-\(sha256Prefix8($0))"
        })
        orphans = Keychain.allClaudeServices()
            .filter { !known.contains($0) && !hidden.contains($0) }
            .map { OrphanEntry(service: $0, credential: Keychain.credential(forService: $0)) }
    }

    // MARK: - Usage

    func hydrateUsageFromCache() async {
        for profile in profiles where profile.provider == .claude {
            let cached = await UsageClient.shared.cached(forService: profile.keychainService)
            if let i = profiles.firstIndex(where: { $0.id == profile.id }), profiles[i].usage == nil {
                profiles[i].usage = cached
            }
        }
    }

    func refreshUsage(force: Bool = false) async {
        guard !isPreview, prefs.showUsageInMenu, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Sequential, and paced: the usage endpoint 429s on back-to-back calls,
        // which was enough to blank a second account on every refresh.
        var networkCalls = 0
        // Iterate a value snapshot: reloading accounts during an await must not
        // invalidate indices or apply a response to another profile.
        for profile in profiles {
            if profile.provider != .claude {
                let reading: ProviderReading
                if profile.provider == .codex {
                    reading = await CodexClient.shared.reading(home: profile.configDir,
                                                              ttl: prefs.usageTTLSeconds, force: force)
                } else {
                    reading = await GrokClient.shared.reading(home: profile.configDir,
                                                             ttl: prefs.usageTTLSeconds, force: force)
                }
                if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[idx].account = reading.account
                    profiles[idx].credential = reading.credential
                    profiles[idx].usage = reading.usage
                }
                continue
            }
            guard profile.isSignedIn else { continue }
            let service = profile.keychainService
            let willHitNetwork = await UsageClient.shared.needsFetch(
                forService: service, ttl: prefs.usageTTLSeconds, force: force)
            if willHitNetwork && networkCalls > 0 {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
            if willHitNetwork { networkCalls += 1 }
            let snap = await UsageClient.shared.usage(forService: service,
                                                      ttl: prefs.usageTTLSeconds,
                                                      force: force)
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx].usage = snap
            }
        }
        await checkLimits()
    }

    // MARK: - Limit alerts

    /// Notifies on a *crossing*, not on a level, so a limit sitting at 90%
    /// doesn't re-alert on every poll.
    private func checkLimits() async {
        guard prefs.notifyEnabled else { return }
        var seen = prefs.lastPercents
        let threshold = prefs.notifyThreshold

        for profile in profiles where profile.isSignedIn {
            guard profile.usage?.error == nil, let bars = profile.usage?.bars else { continue }
            for bar in bars {
                let key = "\(profile.usageKey)|\(bar.kind)"
                let now = bar.percent
                let previous = seen[key]
                seen[key] = now
                guard let previous else { continue }   // nothing to compare yet

                if previous < threshold, now >= threshold {
                    let when = bar.resetsAt.map { " · \(relativeReset($0))" } ?? ""
                    await Notifier.shared.post(
                        title: "\(profile.provider.title) · \(profile.name) is at \(Int(now.rounded()))%",
                        body: "\(bar.label) limit\(when)",
                        id: "\(key)-high")
                } else if prefs.notifyOnReset, previous >= threshold, now < threshold {
                    await Notifier.shared.post(
                        title: "\(profile.provider.title) · \(profile.name) has room again",
                        body: "\(bar.label) dropped to \(Int(now.rounded()))%.",
                        id: "\(key)-reset")
                }
            }
        }
        prefs.lastPercents = seen
        prefs.save()
    }

    // MARK: - Background polling

    /// Alerts are only useful if usage is checked while the menu is closed.
    /// Paced well outside the endpoint's per-account rate limit.
    func startPolling(force: Bool = false) {
        // Opening the menu shouldn't restart the clock every time.
        if !force, pollTimer != nil, prefs.notifyEnabled { return }
        pollTimer?.invalidate()
        pollTimer = nil
        guard prefs.notifyEnabled else { return }
        let interval = max(5, prefs.backgroundPollMinutes) * 60
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
    }

    func enableNotifications(_ on: Bool) {
        prefs.notifyEnabled = on
        prefs.save()
        startPolling(force: true)
        guard on else { notifyStatus = ""; return }
        Task {
            let granted = await Notifier.shared.requestAuthorization()
            let status = await Notifier.shared.authorizationStatus()
            notifyStatus = granted ? "" : "not allowed (\(Notifier.name(status))) — enable Gauge in System Settings › Notifications"
        }
    }

    func sendTestNotification() {
        Task {
            if let error = await Notifier.shared.post(
                title: "Gauge",
                body: "This is what a limit alert looks like.",
                id: "manual-test-\(Int(Date().timeIntervalSince1970))") {
                notifyStatus = error
            } else {
                let status = await Notifier.shared.authorizationStatus()
                notifyStatus = status == .authorized ? "sent" : "sent, but status is \(Notifier.name(status))"
            }
        }
    }

    // MARK: - Resume

    func resume(_ session: RecentSession, in profile: Profile) {
        guard profile.provider == .claude else { return }
        lastError = Launcher.resume(session, profile: profile, prefs: prefs)
        if lastError == nil {
            prefs.lastUsed[profile.id] = Date()
            prefs.save()
        }
    }

    // MARK: - Launching

    func launch(_ profile: Profile) {
        guard checkCLI(for: profile.provider) else { return }
        lastError = Launcher.launch(profile, prefs: prefs)
        if lastError == nil {
            prefs.lastUsed[profile.id] = Date()
            prefs.save()
        }
    }

    /// Config dirs signed into the same Anthropic account share one quota.
    /// Worth surfacing — two profiles is not two allowances.
    func quotaSiblings(of profile: Profile) -> [Profile] {
        guard let uuid = profile.account?.accountUuid, !uuid.isEmpty else { return [] }
        return profiles.filter { $0.provider == profile.provider && $0.id != profile.id && $0.account?.accountUuid == uuid }
    }

    /// True when any signed-in account has crossed the alert threshold. Drives
    /// the menu bar badge, which works with no notification permission at all.
    var anyAccountAtLimit: Bool {
        profiles.contains { p in
            guard p.isSignedIn, let bars = p.usage?.bars else { return false }
            return bars.contains { $0.percent >= prefs.notifyThreshold }
        }
    }

    /// Accounts currently over the threshold, for the dropdown's alert row.
    var accountsAtLimit: [Profile] {
        profiles.filter { p in
            guard p.isSignedIn, let bars = p.usage?.bars else { return false }
            return bars.contains { $0.percent >= prefs.notifyThreshold }
        }
    }

    /// Highest weekly usage across signed-in accounts, for the menu bar readout.
    var menuBarPercent: Double? {
        let recent = profiles
            .filter { $0.isSignedIn && $0.tightestBar != nil }
            .max { (prefs.lastUsed[$0.id] ?? .distantPast) < (prefs.lastUsed[$1.id] ?? .distantPast) }
        return recent?.weeklyPercent ?? recent?.tightestBar?.percent
    }

    func signIn(_ profile: Profile) {
        guard checkCLI(for: profile.provider) else { return }
        lastError = Launcher.signIn(profile, prefs: prefs)
    }

    private func checkCLI(for provider: AIProvider) -> Bool {
        guard provider != .claude, provider.executable == nil else { return true }
        lastError = "Install \(provider.title)\(provider == .grok ? " Build" : "") CLI to connect this account"
        return false
    }

    // MARK: - Profile management

    /// Creates a new config dir and opens the login flow in a terminal.
    func addProfile(name rawName: String, provider: AIProvider = .claude) {
        guard checkCLI(for: provider) else { return }
        let name = rawName.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        guard !name.isEmpty else { lastError = "name required"; return }

        let dir = NSHomeDirectory() + "/.\(provider.rawValue)-" + name
        if FileManager.default.fileExists(atPath: dir) {
            lastError = "\(dir.abbreviatingTilde) already exists"
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
            let filename = provider == .claude ? "settings.json" : "config.toml"
            let contents = provider == .claude ? "{}\n" : "# \(provider.title) account\n"
            try contents.write(toFile: dir + "/" + filename, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let profileID = provider.profileID(for: dir)
        var ov = prefs.overrides[profileID] ?? ProfileOverride()
        ov.name = name
        prefs.overrides[profileID] = ov
        prefs.save()
        reload()

        if let fresh = profiles.first(where: { $0.id == profileID }) {
            // No credentials yet, so run plain `claude` — it starts the login flow.
            lastError = Launcher.signIn(fresh, prefs: prefs)
        }
    }

    /// Removes a profile. The directory goes to the Trash, never rm -rf.
    func removeProfile(_ profile: Profile, deleteDirectory: Bool, deleteCredential: Bool) {
        // These CLIs own their auth stores. Removing them here only hides them.
        if profile.provider != .claude {
            var ov = prefs.overrides[profile.id] ?? ProfileOverride()
            ov.hidden = true
            prefs.overrides[profile.id] = ov
            prefs.save()
            reload()
            return
        }
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
        var ov = prefs.overrides[profile.id] ?? ProfileOverride()
        mutate(&ov)
        prefs.overrides[profile.id] = ov
        prefs.save()

        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        if let name = ov.name, !name.isEmpty { profiles[i].name = name }
        else { profiles[i].name = profile.provider.derivedName(for: profile.configDir) }
        profiles[i].command = ov.command ?? profile.provider.defaultCommand(prefs: prefs)
        profiles[i].workingDir = ov.workingDir
    }

    func savePrefs() {
        prefs.save()
        reload()
    }

    // MARK: - Shell aliases

    /// Appends an alias for a profile into a Gauge-managed block in ~/.zshrc.
    /// Existing hand-written aliases are left completely alone.
    func writeAlias(for profile: Profile, named alias: String) {
        guard alias.range(of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            lastError = "Use letters, numbers, underscores, or hyphens for an alias; start with a letter or underscore"
            return
        }
        let rc = NSHomeDirectory() + "/.zshrc"
        var text = (try? String(contentsOfFile: rc, encoding: .utf8)) ?? ""
        let marker = text.contains("# >>> claudeswitch aliases >>>") ? "claudeswitch" : "gauge"
        let begin = "# >>> \(marker) aliases >>>"
        let end = "# <<< \(marker) aliases <<<"

        // Back up before touching the user's shell config.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        try? text.write(toFile: rc + ".gauge-bak-" + stamp, atomically: true, encoding: .utf8)

        let line = profile.isDefault
            ? "alias \(alias)=\(shellQuote("env -u \(profile.provider.environmentKey) \(profile.command)"))"
            : "alias \(alias)=\(shellQuote("\(profile.provider.environmentKey)=\(shellQuote(profile.configDir)) command \(profile.command)"))"

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
