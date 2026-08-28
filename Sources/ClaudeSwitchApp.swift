import SwiftUI
import AppKit

@main
struct ClaudeSwitchApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            // Glanceable: the bolt, plus the weekly burn of whichever account
            // you launched last.
            HStack(spacing: 3) {
                if let glyph = Art.menuBar {
                    Image(nsImage: glyph)
                } else {
                    Image(systemName: "bolt.fill")
                }
                if state.prefs.showPercentInMenuBar, let pct = state.menuBarPercent {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only; no Dock tile, no window on launch.
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
