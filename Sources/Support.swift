import Foundation
import CryptoKit

// MARK: - Inherited Claude Code session state

/// Claude Code stamps these into the environment of the session it runs in.
///
/// `open` hands the launching process's environment to whatever it starts, so an
/// ClaudeSwitch that was itself launched from inside a Claude session passes them on to
/// every terminal it spawns. That is not cosmetic:
///
///  * `CLAUDE_CODE_CHILD_SESSION` makes the new session think it is a child and
///    silently turns off transcript saving.
///  * `CLAUDE_CODE_MESSAGING_SOCKET` / `_TOKEN` point it at the *parent*
///    session's IPC socket.
///  * `CLAUDE_CODE_EXECPATH` pins it to the parent's CLI version.
///
/// `CLAUDE_CONFIG_DIR` is handled separately — the launch script sets or unsets
/// it per profile.
let claudeSessionMarkers = [
    "CLAUDECODE",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_MESSAGING_SOCKET",
    "CLAUDE_CODE_MESSAGING_TOKEN",
    "CLAUDE_CODE_BRIDGE_SESSION_ID",
    "CLAUDE_CODE_EXECPATH",
    "CLAUDE_PID",
    "CLAUDE_EFFORT",
    "AI_AGENT",
]

// MARK: - Shell helpers

/// Wrap a string in single quotes so it survives /bin/zsh -c intact.
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct RunResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
}

/// Run an executable and capture its output. Never used for anything interactive.
@discardableResult
func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) -> RunResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    // Never pass our own Claude session state to anything we spawn. The
    // generated launch script unsets these too, so this is belt and braces for
    // however ClaudeSwitch itself was started.
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
    for key in claudeSessionMarkers { env.removeValue(forKey: key) }
    p.environment = env
    do { try p.run() } catch {
        return RunResult(status: -1, stdout: "", stderr: error.localizedDescription)
    }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return RunResult(status: p.terminationStatus,
                     stdout: String(data: o, encoding: .utf8) ?? "",
                     stderr: String(data: e, encoding: .utf8) ?? "")
}

// MARK: - Hashing

/// Claude Code derives its keychain service suffix from the absolute config-dir
/// path: "Claude Code-credentials-" + first 8 hex chars of sha256(path).
func sha256Prefix8(_ s: String) -> String {
    let digest = SHA256.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(8).lowercased()
}

// MARK: - Formatting

func relativeReset(_ date: Date?) -> String {
    guard let date else { return "" }
    let secs = date.timeIntervalSinceNow
    if secs <= 0 { return "resetting" }
    let h = Int(secs) / 3600, m = (Int(secs) % 3600) / 60
    if h >= 48 { return "resets in \(h / 24)d" }
    if h >= 1 { return "resets in \(h)h \(m)m" }
    return "resets in \(m)m"
}

func shortDate(_ date: Date?) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.dateFormat = "d MMM, HH:mm"
    return f.string(from: date)
}

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
    var abbreviatingTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}
