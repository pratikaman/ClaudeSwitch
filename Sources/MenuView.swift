import SwiftUI
import AppKit

// MARK: - Account row

struct ProfileRow: View {
    @EnvironmentObject var state: AppState
    let profile: Profile
    let index: Int
    @State private var hovering = false

    private var accent: Color { Theme.palette[profile.accentIndex] }
    private var siblings: [Profile] { state.quotaSiblings(of: profile) }

    var body: some View {
        // A real Button, not a tap gesture: keyboardShortcut only binds to
        // controls, so ⌘1…⌘9 would silently do nothing on a plain view.
        Button {
            profile.isSignedIn ? state.launch(profile) : state.signIn(profile)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Monogram(text: profile.name, color: accent, size: 30)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(profile.name)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let cred = profile.credential {
                            Chip(text: cred.tierLabel, color: accent)
                        }
                        if profile.isDefault, profile.name.lowercased() != "default" {
                            Chip(text: "default", color: Theme.dim)
                        }
                        Spacer(minLength: 0)
                        if index < 9 {
                            Text("⌘\(index + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(hovering ? Theme.brand : Theme.faint)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(profile.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let alias = profile.alias {
                            Text(alias)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                        }
                    }

                    detail
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softSurface(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Launch") { state.launch(profile) }
            let recent = state.sessions[profile.configDir] ?? []
            if !recent.isEmpty {
                Menu("Resume") {
                    ForEach(recent) { session in
                        Button("\(session.title)  —  \(session.projectName)") {
                            state.resume(session, in: profile)
                        }
                    }
                }
            }
            Button("Sign in / switch account…") { state.signIn(profile) }
            Divider()
            Button("Open config folder") { Launcher.revealInFinder(profile.configDir) }
            Button("Copy config dir path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(profile.configDir, forType: .string)
            }
        }
        .help("Opens \(state.prefs.terminal.displayName) with CLAUDE_CONFIG_DIR=\(profile.shortDir)")
    }

    @ViewBuilder
    private var detail: some View {
        if !profile.isSignedIn {
            HStack(spacing: 5) {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 10))
                Text("tap to sign in").font(.system(size: 10.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.amber)
            .padding(.top, 1)
        } else if state.prefs.showUsageInMenu {
            if let usage = profile.usage, !usage.bars.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(usage.bars) { MiniBar(bar: $0, height: 5) }
                    if !siblings.isEmpty {
                        Text("shares quota with \(siblings.map(\.name).joined(separator: ", "))")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.purple)
                    }
                }
                .padding(.top, 2)
            } else {
                Text(profile.usage?.friendlyError ?? "loading usage…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

// MARK: - Dropdown

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if state.profiles.isEmpty {
                emptyState
            } else {
                Hairline()
                sectionHeader

                if state.profiles.count > 4 {
                    ScrollView { accountList }
                        .frame(height: 300)
                        .scrollIndicators(.never)
                } else {
                    accountList
                }
            }

            if !state.accountsAtLimit.isEmpty {
                Hairline()
                limitStrip
            }
            if !state.orphans.isEmpty {
                Hairline()
                orphanStrip
            }
            if let err = state.lastError {
                Hairline()
                errorLine(err)
            }

            Hairline()
            footer
        }
        .frame(width: 356)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task { await state.refreshUsage() }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.profiles.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Hairline(inset: 55) }
                ProfileRow(profile: p, index: i)
                    .keyboardShortcut(i < 9 ? KeyEquivalent(Character("\(i + 1)")) : "0",
                                      modifiers: .command)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 7) {
            MascotMark(height: 18)
            Wordmark()
            Spacer()
            CircleButton(symbol: "arrow.clockwise") {
                Task { await state.refreshUsage(force: true) }
            }
            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
            .animation(state.isRefreshing
                       ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                       : .default, value: state.isRefreshing)
            .help("Refresh usage")
            CircleButton(symbol: "slider.horizontal.3") { openManager(tab: 0) }
                .help("Manage accounts")
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 14)
    }

    private var sectionHeader: some View {
        HStack {
            SectionLabel(text: "ALL ACCOUNTS")
            Spacer()
            Text("\(state.profiles.filter(\.isSignedIn).count)/\(state.profiles.count) signed in")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            MascotMark(height: 40).opacity(0.5)
            Text("No Claude accounts yet")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Add one and ClaudeSwitch will run the login flow for you.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            ActionButton(title: "Add an account", symbol: "plus") { openManager(tab: 0) }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
    }

    /// Shown when an account crosses the alert threshold. This is the layer
    /// that needs no notification permission, so it always works.
    private var limitStrip: some View {
        let hit = state.accountsAtLimit
        let worst = hit.compactMap(\.tightestBar).max { $0.percent < $1.percent }
        return HoverRow { openManager(tab: 2) } content: {
            HStack(spacing: 9) {
                Capsule().fill(Theme.alert).frame(width: 2.5, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.count == 1
                         ? "\(hit[0].name) is at \(Int((worst?.percent ?? 0).rounded()))%"
                         : "\(hit.count) accounts are near their limit")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(worst?.resetsAt.map { "\(worst?.label ?? "limit") · \(relativeReset($0))" }
                         ?? "over \(Int(state.prefs.notifyThreshold))%")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
        }
    }

    /// An inline strip with an accent edge, rather than another outlined box.
    private var orphanStrip: some View {
        HoverRow { openManager(tab: 1) } content: {
            HStack(spacing: 9) {
                Capsule().fill(Theme.amber).frame(width: 2.5, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(state.orphans.count) leftover login\(state.orphans.count == 1 ? "" : "s") in your keychain")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("from config folders that no longer exist")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private func errorLine(_ err: String) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(Theme.alert).frame(width: 2.5, height: 20)
            Text(err).font(.system(size: 10)).lineLimit(2).foregroundStyle(Theme.alert)
            Spacer()
            Button { state.lastError = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            PillButton(title: "add", symbol: "plus", color: Theme.brand) { openManager(tab: 0) }
            PillButton(title: "manage", symbol: "gearshape.fill") { openManager(tab: 0) }
            Spacer()
            PillButton(title: "quit", color: Theme.dim) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openManager(tab: Int) {
        state.managerTab = tab
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "manager")
    }
}

/// A borderless row that only shows a surface while the pointer is over it.
struct HoverRow<C: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> C
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softSurface(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
