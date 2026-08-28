import Foundation
import UserNotifications

/// Local notifications for rate-limit thresholds.
///
/// The app is ad-hoc signed and unsandboxed, which historically makes
/// UNUserNotificationCenter unreliable, so every call reports its outcome
/// rather than failing silently — see `selfTest()`.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private(set) var lastError: String?

    /// Asks once; macOS remembers the answer per bundle id.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Posts immediately. Returns an error description, or nil on success.
    ///
    /// Ad-hoc signing gives the bundle a new code signature on every build, so
    /// `usernoted` never registers it and `requestAuthorization` returns denied
    /// without ever prompting. When that happens we fall back to AppleScript,
    /// which posts through an already-registered bundle. The menu bar badge is
    /// the third layer and needs no permission at all.
    @discardableResult
    func post(title: String, body: String, id: String = UUID().uuidString) async -> String? {
        if await authorizationStatus() != .authorized {
            return postViaAppleScript(title: title, body: body)
        }
        return await postNative(title: title, body: body, id: id)
    }

    private func postViaAppleScript(title: String, body: String) -> String? {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
        let r = run("/usr/bin/osascript", ["-e", script])
        lastError = r.ok ? nil : (r.stderr.isEmpty ? "osascript failed" : r.stderr)
        return lastError
    }

    private func postNative(title: String, body: String, id: String) async -> String? {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastError = nil
            return nil
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    /// Launch with CLAUDESWITCH_NOTIFY_SELFTEST=1 to write the authorization
    /// status and delivery result to disk. Used to verify notifications work at
    /// all in an ad-hoc signed bundle, where they cannot be clicked to check.
    func selfTest() async {
        trace("start; bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        trace("center obtained")
        let granted = await requestAuthorization()
        trace("requestAuthorization returned \(granted)")
        let status = await authorizationStatus()
        trace("status = \(Self.name(status))")
        let error = await post(title: "ClaudeSwitch",
                               body: "Notifications are working.",
                               id: "selftest")
        trace("post returned \(error ?? "success")")
        let report: [String: Any] = [
            "granted": granted,
            "status": status.rawValue,
            "statusName": Self.name(status),
            "postError": error ?? "none",
            "bundleID": Bundle.main.bundleIdentifier ?? "nil",
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
            try? data.write(to: Paths.support.appendingPathComponent("notify-selftest.json"))
        }
    }

    /// Appends a step marker so a hang can be located from outside the app.
    private func trace(_ line: String) {
        let url = Paths.support.appendingPathComponent("notify-trace.log")
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp)  \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func name(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        @unknown default: return "unknown(\(s.rawValue))"
        }
    }
}
