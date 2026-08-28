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

    // Limit alerts
    var notifyEnabled = true
    var notifyThreshold: Double = 85
    var notifyOnReset = true
    var backgroundPollMinutes: Double = 15
    /// Last seen percentage per "keychainService|barKind", so a crossing can be
    /// detected instead of re-alerting on every poll.
    var lastPercents: [String: Double] = [:]

    // Recent sessions
    var showRecentSessions = true

    /// Decodes field by field, falling back to the default for anything absent.
    ///
    /// Synthesized Codable requires *every* non-optional key to be present, so
    /// shipping a new preference made the whole file fail to decode — load()
    /// returned defaults and the next save silently destroyed the user's
    /// display names, working dirs and history. Adding a field must never do
    /// that, so decoding is tolerant by construction.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Prefs()
        terminal             = v(.terminal, d.terminal)
        defaultCommand       = v(.defaultCommand, d.defaultCommand)
        keepShellOpen        = v(.keepShellOpen, d.keepShellOpen)
        usageTTLSeconds      = v(.usageTTLSeconds, d.usageTTLSeconds)
        showUsageInMenu      = v(.showUsageInMenu, d.showUsageInMenu)
        extraPaths           = v(.extraPaths, d.extraPaths)
        overrides            = v(.overrides, d.overrides)
        lastUsed             = v(.lastUsed, d.lastUsed)
        showPercentInMenuBar = v(.showPercentInMenuBar, d.showPercentInMenuBar)
        notifyEnabled        = v(.notifyEnabled, d.notifyEnabled)
        notifyThreshold      = v(.notifyThreshold, d.notifyThreshold)
        notifyOnReset        = v(.notifyOnReset, d.notifyOnReset)
        backgroundPollMinutes = v(.backgroundPollMinutes, d.backgroundPollMinutes)
        lastPercents         = v(.lastPercents, d.lastPercents)
        showRecentSessions   = v(.showRecentSessions, d.showRecentSessions)
    }

    init() {}

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
