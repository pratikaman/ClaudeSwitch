import SwiftUI
import AppKit

/// Renders synthetic data only. Preview AppState never discovers or polls accounts.
@MainActor
enum DesignPreview {
    static func render() throws {
        let output = URL(fileURLWithPath: "build/design", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let state = AppState(previewProfiles: profiles)
        try snapshot(ManagerView().environmentObject(state), size: NSSize(width: 880, height: 680),
                     to: output.appendingPathComponent("accounts.png"))
        try snapshot(MenuView().environmentObject(state), size: NSSize(width: 400, height: 650),
                     to: output.appendingPathComponent("menu.png"))
        state.providerFilter = .grok
        try snapshot(ManagerView().environmentObject(state), size: NSSize(width: 880, height: 680),
                     to: output.appendingPathComponent("grok.png"))
        state.managerTab = 2
        try snapshot(ManagerView().environmentObject(state), size: NSSize(width: 880, height: 680),
                     to: output.appendingPathComponent("preferences.png"))
        let empty = AppState(previewProfiles: [])
        try snapshot(MenuView().environmentObject(empty), size: NSSize(width: 400, height: 380),
                     to: output.appendingPathComponent("empty.png"))
        print("Rendered synthetic Gauge screens in build/design/")
    }

    private static func snapshot<V: View>(_ content: V, size: NSSize, to url: URL) throws {
        let view = NSHostingView(rootView: content)
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "GaugePreview", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GaugePreview", code: 2)
        }
        try data.write(to: url)
    }

    private static var profiles: [Profile] {
        let samples: [(AIProvider, String, String, Double, Double)] = [
            (.claude, "Personal", "Max", 34, 61),
            (.claude, "Studio", "Pro", 88, 73),
            (.codex, "Work", "Plus", 18, 42),
            (.grok, "Personal", "SuperGrok", 0, 27)
        ]
        return samples.map { provider, name, plan, session, week in
            var bars = [LimitBar(kind: "week", label: "week", percent: week,
                                 resetsAt: Date().addingTimeInterval(273600), severity: "normal")]
            if provider != .grok {
                bars.insert(LimitBar(kind: "5h", label: "5h", percent: session,
                                     resetsAt: Date().addingTimeInterval(8100), severity: "normal"), at: 0)
            }
            return Profile(configDir: "/example/.\(provider.rawValue)-\(name.lowercased())",
                           isDefault: false, name: name,
                           account: Account(email: "\(name.lowercased())@example.com", displayName: name,
                                            organizationName: "", organizationType: plan,
                                            organizationRole: "", accountUuid: ""),
                           credential: Credential(scopes: [], subscriptionType: plan, rateLimitTier: ""),
                           command: provider.rawValue, usage: UsageSnapshot(bars: bars, fetchedAt: Date(), error: nil),
                           provider: provider)
        }
    }
}
