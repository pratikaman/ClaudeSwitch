import Foundation

enum Paths {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeSwitch", isDirectory: true)
    }
    static var launchScripts: URL {
        support.appendingPathComponent("launch", isDirectory: true)
    }
    static var configFile: URL {
        support.appendingPathComponent("config.json")
    }
}

enum TerminalApp: String, CaseIterable, Codable, Identifiable {
    case ghostty, terminal, iterm, warp, kitty
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .warp: return "Warp"
        case .kitty: return "kitty"
        }
    }

    var bundlePath: String {
        switch self {
        case .ghostty: return "/Applications/Ghostty.app"
        case .terminal: return "/System/Applications/Utilities/Terminal.app"
        case .iterm: return "/Applications/iTerm.app"
        case .warp: return "/Applications/Warp.app"
        case .kitty: return "/Applications/kitty.app"
        }
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: bundlePath) }

    static var installed: [TerminalApp] { allCases.filter(\.isInstalled) }
}

/// Per-profile settings the user has customised. Anything not overridden falls
/// back to a value derived from the config dir itself.
struct ProfileOverride: Codable, Equatable {
    var name: String?
    var command: String?
    var workingDir: String?
    var hidden: Bool = false
    var order: Int = 0
}

struct Prefs: Codable, Equatable {
    var terminal: TerminalApp = .ghostty
    var defaultCommand: String = "claude --dangerously-skip-permissions"
    var keepShellOpen: Bool = true
    var usageTTLSeconds: Double = 300
    var showUsageInMenu: Bool = true
    var extraPaths: [String] = []
    var overrides: [String: ProfileOverride] = [:]
    var lastUsed: [String: Date] = [:]
    var showPercentInMenuBar = true

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: Paths.configFile),
              let p = try? JSONDecoder().decode(Prefs.self, from: data)
        else { return Prefs() }
        return p
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Paths.configFile)
    }
}
