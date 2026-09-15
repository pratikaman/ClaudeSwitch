import Foundation
import CoreFoundation

func usageNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
}

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, codex, grok

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var environmentKey: String {
        switch self {
        case .claude: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .grok: return "GROK_HOME"
        }
    }
    var defaultDir: String { NSHomeDirectory() + "/." + rawValue }
    var loginCommand: String { self == .claude ? "command claude /login" : "command \(rawValue) login" }

    func profileID(for dir: String) -> String {
        self == .claude ? dir : "\(rawValue):\(dir)"
    }

    func defaultCommand(prefs: Prefs) -> String {
        self == .claude ? prefs.defaultCommand : rawValue
    }

    var executable: String? {
        let home = NSHomeDirectory()
        let candidates = [home + "/.local/bin/\(rawValue)", home + "/.\(rawValue)/bin/\(rawValue)",
                          "/opt/homebrew/bin/\(rawValue)", "/usr/local/bin/\(rawValue)",
                          "/Applications/\(title).app/Contents/Resources/\(rawValue)"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .map { String($0) + "/\(rawValue)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func derivedName(for dir: String) -> String {
        if dir == defaultDir { return "default" }
        let base = (dir as NSString).lastPathComponent
        let prefix = ".\(rawValue)-"
        return base.hasPrefix(prefix) ? String(base.dropFirst(prefix.count)) : base
    }
}

/// CLIs own authentication and token refresh. Discovery only looks for homes;
/// each provider's client reads account metadata later.
enum CLIAccountDiscovery {
    static func configDirs(extraPaths: [String], provider: AIProvider = .codex, home: String = NSHomeDirectory(),
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        var candidates = [home + "/.\(provider.rawValue)"]
        candidates += entries.sorted().filter { $0.hasPrefix(".\(provider.rawValue)-") }.map { home + "/" + $0 }
        if let configured = environment[provider.environmentKey], !configured.isEmpty { candidates.append(configured) }
        candidates += extraPaths
        var seen = Set<String>()
        return candidates.compactMap { raw in
            let path = URL(fileURLWithPath: raw.expandingTilde).standardizedFileURL.path
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &directory), directory.boolValue,
                  ["auth.json", "config.toml"].contains(where: { fm.fileExists(atPath: path + "/" + $0) }),
                  seen.insert(path).inserted else { return nil }
            return path
        }
    }
}
