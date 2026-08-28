import SwiftUI
import AppKit
import UserNotifications

@main
struct ClaudeSwitchApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
                .task { state.startPolling() }
        } label: {
            // Glanceable: the bolt, plus the weekly burn of whichever account
            // you launched last.
            HStack(spacing: 3) {
                if let glyph = Art.menuBar {
                    Image(nsImage: glyph)
                } else {
                    Image(systemName: "bolt.fill")
                }
                if state.anyAccountAtLimit {
                    Text("!")
                } else if state.prefs.showPercentInMenuBar, let pct = state.menuBarPercent {
                    Text("\(Int(pct.rounded()))%")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("ClaudeSwitch", id: "manager") {
            ManagerView()
                .environmentObject(state)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only; no Dock tile, no window on launch.
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        // Verification hook: notifications can't be clicked in an LSUIElement
        // app, so this writes the authorization + delivery result to disk.
        if ProcessInfo.processInfo.environment["CLAUDESWITCH_NOTIFY_SELFTEST"] == "1" {
            Task { @MainActor in await Notifier.shared.selfTest() }
        }
    }

    /// A menu bar app is never "frontmost" in the usual sense, so banners have
    /// to be requested explicitly or they'd only appear in Notification Centre.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
                                -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
