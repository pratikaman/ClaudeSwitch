import SwiftUI
import AppKit

/// Sections are a label plus content on the plain background. Wrapping each one
/// in an outlined card made every screen read as a stack of boxes.
struct Section<C: View>: View {
    let title: String
    @ViewBuilder var content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ManagerView: View {
    @EnvironmentObject var state: AppState

    private let tabs = [("Accounts", "person.2.fill"),
                        ("Keychain", "key.fill"),
                        ("Settings", "slider.horizontal.3")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MascotMark(height: 20)
                Wordmark(size: 17)
                Text("account manager")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faint)
                Spacer()
                segmented
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 14)

            Hairline()

            Group {
                switch state.managerTab {
                case 1:  KeychainTab()
                case 2:  SettingsTab()
                default: ProfilesTab()
                }
            }
        }
        .frame(width: 660, height: 534)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                let active = state.managerTab == i
                Button { state.managerTab = i } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.1).font(.system(size: 9.5, weight: .bold))
                        Text(tab.0).font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(active ? Theme.bg : Theme.dim)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(active ? Theme.brand : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Accounts

struct ProfilesTab: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    @State private var selection: String?
    @State private var confirmRemove: Profile?

    private var selected: Profile? {
        state.profiles.first { $0.configDir == selection } ?? state.profiles.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            if let p = selected {
                detail(p)
            } else {
                Spacer()
            }
        }
        .alert(item: $confirmRemove) { p in
            Alert(
                title: Text("Remove “\(p.name)”?"),
                message: Text("Moves \(p.shortDir) to the Trash and deletes its keychain login. Sessions, settings and history in that folder go with it."),
                primaryButton: .destructive(Text("Move to Trash")) {
                    state.removeProfile(p, deleteDirectory: true, deleteCredential: true)
                    selection = nil
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(state.profiles.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Hairline(inset: 50) }
                        sidebarRow(p)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "NEW ACCOUNT")
                WellField(placeholder: "name, e.g. work", text: $newName)
                ActionButton(title: "Add & sign in", symbol: "plus", height: 34,
                             showChevron: false) {
                    state.addProfile(name: newName)
                    newName = ""
                }
                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("Creates ~/.claude-<name> and opens the login flow.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func sidebarRow(_ p: Profile) -> some View {
        let active = (selected?.configDir == p.configDir)
        let accent = Theme.palette[p.accentIndex]
        return Button { selection = p.configDir } label: {
            HStack(spacing: 10) {
                // Selection reads as an accent edge, not an outlined tile.
                Capsule()
                    .fill(active ? accent : .clear)
                    .frame(width: 2.5, height: 26)
                Monogram(text: p.name, color: accent, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .white : Color.white.opacity(0.82))
                        .lineLimit(1)
                    Text(p.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(p.isSignedIn ? Theme.dim : Theme.amber)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softSurface(active, radius: 0, opacity: 0.05)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detail(_ p: Profile) -> some View {
        let accent = Theme.palette[p.accentIndex]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Monogram(text: p.name, color: accent, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(p.name)
                                .font(.system(size: 21, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            if let c = p.credential { Chip(text: c.tierLabel, color: accent) }
                            if p.isDefault, p.name.lowercased() != "default" {
                                Chip(text: "default", color: Theme.dim)
                            }
                        }
                        Text(p.account.map { "\($0.displayName) · \($0.email)" } ?? "not signed in")
                            .font(.system(size: 11))
                            .foregroundStyle(p.isSignedIn ? Theme.dim : Theme.amber)
                    }
                    Spacer()
                    ActionButton(title: "Launch", height: 34, showChevron: false) {
                        state.launch(p)
                    }
                    .frame(width: 134)
                }

                if !state.quotaSiblings(of: p).isEmpty {
                    HStack(spacing: 7) {
                        Capsule().fill(Theme.purple).frame(width: 2.5, height: 20)
                        Text("Same Anthropic account as \(state.quotaSiblings(of: p).map(\.name).joined(separator: ", ")) — they share one rate limit.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.purple)
                    }
                }

                Hairline()

                Section(title: "UNDER THE HOOD") {
                    VStack(alignment: .leading, spacing: 6) {
                        kv("Config dir", p.shortDir, mono: true)
                        kv("Keychain", p.keychainService, mono: true)
                        if let a = p.account {
                            kv("Organization", "\(a.organizationName) · \(a.planLabel) · \(a.organizationRole)")
                        }
                        if let c = p.credential {
                            kv("Token expires", shortDate(c.expiresAt) + (c.isExpired ? "  (expired)" : ""))
                            kv("Refresh expires", shortDate(c.refreshExpiresAt))
                        } else {
                            HStack(spacing: 8) {
                                Text("No login stored").font(.system(size: 11))
                                    .foregroundStyle(Theme.amber)
                                PillButton(title: "sign in", symbol: "person.badge.key.fill",
                                           color: Theme.amber) { state.signIn(p) }
                            }
                        }
                    }
                }

                Hairline()

                Section(title: "WHEN YOU LAUNCH IT") {
                    VStack(alignment: .leading, spacing: 9) {
                        labelled("Command") {
                            WellField(placeholder: state.prefs.defaultCommand, mono: true, text: Binding(
                                get: { p.command },
                                set: { v in state.update(p) { $0.command = v.isEmpty ? nil : v } }))
                        }
                        labelled("Folder") {
                            HStack(spacing: 7) {
                                WellField(placeholder: "home", text: Binding(
                                    get: { p.workingDir ?? "" },
                                    set: { v in state.update(p) { $0.workingDir = v.isEmpty ? nil : v } }))
                                PillButton(title: "choose") { chooseDir(for: p) }
                            }
                        }
                        labelled("Display name") {
                            WellField(placeholder: Discovery.derivedName(for: p.configDir), text: Binding(
                                get: { p.name },
                                set: { v in state.update(p) { $0.name = v.isEmpty ? nil : v } }))
                        }
                    }
                }

                Hairline()

                HStack {
                    if let alias = p.alias {
                        Text("shell alias").font(.system(size: 10)).foregroundStyle(Theme.faint)
                        Text(alias)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.brand)
                    } else {
                        PillButton(title: "add zsh alias", symbol: "terminal.fill",
                                   color: Theme.brand) { addAlias(for: p) }
                            .help("Appends to an ClaudeSwitch-managed block in ~/.zshrc, after a backup. Your own aliases are never touched.")
                    }
                    Spacer()
                    if !p.isDefault {
                        PillButton(title: "remove account", symbol: "trash.fill",
                                   color: Theme.alert) { confirmRemove = p }
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.never)
    }

    private func kv(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                .frame(width: 106, alignment: .leading)
            Text(v)
                .font(.system(size: 10.5, weight: mono ? .medium : .regular,
                              design: mono ? .monospaced : .default))
                .foregroundStyle(Theme.dim)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                .frame(width: 106, alignment: .leading)
            content()
        }
    }

    private func chooseDir(for p: Profile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.update(p) { $0.workingDir = url.path }
        }
    }

    private func addAlias(for p: Profile) {
        let alert = NSAlert()
        alert.messageText = "Alias for “\(p.name)”"
        alert.informativeText = "Appended to an ClaudeSwitch-managed block at the end of ~/.zshrc. A timestamped backup is written first."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = Discovery.derivedName(for: p.configDir)
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { state.writeAlias(for: p, named: name) }
        }
    }
}

// MARK: - Keychain

struct KeychainTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Claude Code keeps each config folder's login in your keychain under “Claude Code-credentials-<first 8 hex of sha256(folder path)>”. The default ~/.claude uses the plain name. Delete a config folder and its login stays behind — still holding a working refresh token.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                Hairline()

                Section(title: "IN USE") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(state.profiles) { p in
                            HStack(spacing: 8) {
                                Image(systemName: p.isSignedIn ? "key.fill" : "key.slash.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(p.isSignedIn ? Theme.brand : Theme.amber)
                                    .frame(width: 14)
                                Text(p.keychainService)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.dim)
                                Chip(text: p.name, color: Theme.palette[p.accentIndex])
                                Spacer()
                                Text(p.credential.map {
                                    $0.isExpired ? "expired" : "expires \(shortDate($0.expiresAt))"
                                } ?? "no login")
                                    .font(.system(size: 10))
                                    .foregroundStyle((p.credential?.isExpired ?? true) ? Theme.amber : Theme.faint)
                            }
                        }
                    }
                }

                Hairline()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionLabel(text: "LEFTOVERS")
                        Spacer()
                        if !state.orphans.isEmpty {
                            PillButton(title: "delete all \(state.orphans.count)", symbol: "trash.fill",
                                       color: Theme.alert) { state.confirmDeleteAllOrphans() }
                        }
                    }
                    if state.orphans.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 11))
                            Text("All clean — every login maps to a folder.").font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.brand)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(state.orphans.enumerated()), id: \.element.id) { i, o in
                                if i > 0 { Hairline() }
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10)).foregroundStyle(Theme.amber)
                                        .frame(width: 14)
                                    Text(o.service)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.dim)
                                    if let c = o.credential {
                                        Chip(text: c.tierLabel, color: Theme.amber)
                                        Text("live token").font(.system(size: 9))
                                            .foregroundStyle(Theme.amber)
                                    } else {
                                        Text("no token data").font(.system(size: 9))
                                            .foregroundStyle(Theme.faint)
                                    }
                                    Spacer()
                                    PillButton(title: "delete", color: Theme.alert) {
                                        state.deleteOrphan(o)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    PillButton(title: "rescan", symbol: "arrow.clockwise") { state.reload() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Section(title: "LAUNCHING") {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("Terminal").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            segmentedPills(TerminalApp.installed.map { ($0.displayName, $0) },
                                           current: state.prefs.terminal) {
                                state.prefs.terminal = $0; state.savePrefs()
                            }
                        }
                        HStack {
                            Text("Default command")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 130, alignment: .leading)
                            WellField(placeholder: "claude", mono: true, text: Binding(
                                get: { state.prefs.defaultCommand },
                                set: { state.prefs.defaultCommand = $0; state.prefs.save() }))
                        }
                        ToggleRow(title: "Keep the shell open",
                                  subtitle: "Stay in the terminal after Claude exits",
                                  isOn: Binding(get: { state.prefs.keepShellOpen },
                                                set: { state.prefs.keepShellOpen = $0; state.savePrefs() }))
                    }
                }

                Hairline()

                Section(title: "USAGE") {
                    VStack(alignment: .leading, spacing: 11) {
                        ToggleRow(title: "Show rate-limit bars",
                                  subtitle: "Usage on each account",
                                  isOn: Binding(get: { state.prefs.showUsageInMenu },
                                                set: { state.prefs.showUsageInMenu = $0; state.savePrefs() }))
                        ToggleRow(title: "Percentage in the menu bar",
                                  subtitle: "Weekly usage of the account you used last",
                                  isOn: Binding(get: { state.prefs.showPercentInMenuBar },
                                                set: { state.prefs.showPercentInMenuBar = $0; state.savePrefs() }))
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Refresh at most every")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                Text("The endpoint rate-limits per account under frequent polling")
                                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            segmentedPills([("1m", 60.0), ("5m", 300.0), ("15m", 900.0), ("1h", 3600.0)],
                                           current: state.prefs.usageTTLSeconds, width: 34) {
                                state.prefs.usageTTLSeconds = $0; state.savePrefs()
                            }
                        }
                    }
                }

                Hairline()

                Section(title: "LIMIT ALERTS") {
                    VStack(alignment: .leading, spacing: 11) {
                        ToggleRow(title: "Tell me when a limit is close",
                                  subtitle: "Checks in the background and alerts on a crossing",
                                  isOn: Binding(get: { state.prefs.notifyEnabled },
                                                set: { state.enableNotifications($0) }))
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Alert above")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                Text("Of whichever limit is closest to biting")
                                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            segmentedPills([("75%", 75.0), ("85%", 85.0), ("95%", 95.0)],
                                           current: state.prefs.notifyThreshold, width: 40) {
                                state.prefs.notifyThreshold = $0; state.savePrefs()
                            }
                        }
                        ToggleRow(title: "Also tell me when it frees up",
                                  subtitle: "When a window resets and you have room again",
                                  isOn: Binding(get: { state.prefs.notifyOnReset },
                                                set: { state.prefs.notifyOnReset = $0; state.savePrefs() }))
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Check every")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                Text("Kept well inside the endpoint's rate limit")
                                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            segmentedPills([("10m", 10.0), ("15m", 15.0), ("30m", 30.0), ("1h", 60.0)],
                                           current: state.prefs.backgroundPollMinutes, width: 38) {
                                state.prefs.backgroundPollMinutes = $0
                                state.savePrefs()
                                state.startPolling(force: true)
                            }
                        }
                        HStack(spacing: 8) {
                            PillButton(title: "send a test alert", symbol: "bell.badge",
                                       color: Theme.brand) { state.sendTestNotification() }
                            if !state.notifyStatus.isEmpty {
                                Text(state.notifyStatus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(state.notifyStatus == "sent" ? Theme.brand : Theme.amber)
                            }
                            Spacer()
                        }
                        Text("The app is ad-hoc signed, so macOS never registers it for native notifications — alerts are posted through AppleScript instead, and the menu bar shows a “!” regardless.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Hairline()

                Section(title: "RECENT SESSIONS") {
                    ToggleRow(title: "Offer to resume past conversations",
                              subtitle: "Reads each account's transcripts to list what you were last doing",
                              isOn: Binding(get: { state.prefs.showRecentSessions },
                                            set: { state.prefs.showRecentSessions = $0; state.savePrefs() }))
                }

                Hairline()

                Section(title: "WHAT CLAUDESWITCH WON'T DO") {
                    Text("ClaudeSwitch never edits ~/.claude, never swaps keychain entries, and never rewrites aliases you wrote yourself. Picking an account only sets CLAUDE_CONFIG_DIR for the terminal window it opens — and the default account launches with that variable unset, so it matches a plain `claude`.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.never)
    }

    /// Capsule choice group, used instead of a boxy Picker.
    private func segmentedPills<T: Equatable>(_ items: [(String, T)], current: T,
                                              width: CGFloat? = nil,
                                              select: @escaping (T) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let active = item.1 == current
                Button { select(item.1) } label: {
                    Text(item.0)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Theme.bg : Theme.dim)
                        .padding(.horizontal, width == nil ? 11 : 0)
                        .frame(width: width, height: 24)
                        .background(Capsule().fill(active ? Theme.brand : Color.white.opacity(0.06)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
