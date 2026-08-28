import Foundation

/// Finds Claude Code config directories and reads the account behind each one.
enum Discovery {
    static var home: String { NSHomeDirectory() }
    static var defaultDir: String { home + "/.claude" }

    /// ~/.claude plus every ~/.claude-* sibling that looks like a config dir,
    /// plus any extra paths the user has added by hand.
    static func configDirs(extraPaths: [String]) -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []

        if looksLikeConfigDir(defaultDir) { dirs.append(defaultDir) }

        let entries = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        for entry in entries.sorted() where entry.hasPrefix(".claude-") {
            let path = home + "/" + entry
            // ~/.claude-switcher and friends are not config dirs.
            if looksLikeConfigDir(path) { dirs.append(path) }
        }

        for extra in extraPaths {
            let path = extra.expandingTilde
            if !dirs.contains(path), looksLikeConfigDir(path) { dirs.append(path) }
        }
        return dirs
    }

    /// A config dir is one holding a .claude.json, or an empty dir the user
    /// registered explicitly (a profile awaiting its first login).
    static func looksLikeConfigDir(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else { return false }
        return FileManager.default.fileExists(atPath: path + "/.claude.json")
            || FileManager.default.fileExists(atPath: path + "/settings.json")
    }

    /// Reads oauthAccount out of <dir>/.claude.json.
    static func account(in dir: String) -> Account? {
        let path = dir + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let o = root["oauthAccount"] as? [String: Any],
              let email = o["emailAddress"] as? String
        else { return nil }

        return Account(
            email: email,
            displayName: o["displayName"] as? String ?? "",
            organizationName: o["organizationName"] as? String ?? "",
            organizationType: o["organizationType"] as? String ?? "",
            organizationRole: o["organizationRole"] as? String ?? "",
            accountUuid: o["accountUuid"] as? String ?? ""
        )
    }

    /// A readable default name for a dir: ~/.claude-work -> "work".
    static func derivedName(for dir: String) -> String {
        if dir == defaultDir { return "default" }
        let base = (dir as NSString).lastPathComponent
        if base.hasPrefix(".claude-") { return String(base.dropFirst(".claude-".count)) }
        return base.hasPrefix(".") ? String(base.dropFirst()) : base
    }

    /// Scans ~/.zshrc for aliases that point at a config dir, so ClaudeSwitch can show
    /// the shell command you already use for each profile. Read-only.
    static func aliases() -> [String: String] {   // configDir -> alias name
        guard let text = try? String(contentsOfFile: home + "/.zshrc", encoding: .utf8)
        else { return [:] }

        var map: [String: String] = [:]
        // alias name="CLAUDE_CONFIG_DIR=~/.claude-foo command claude ..."
        let pattern = #"alias\s+([A-Za-z0-9_-]+)\s*=\s*["']?[^"'\n]*CLAUDE_CONFIG_DIR=([^\s"']+)"#
        let re = try? NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        re?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            let name = ns.substring(with: m.range(at: 1))
            let dir = ns.substring(with: m.range(at: 2)).expandingTilde
            if map[dir] == nil { map[dir] = name }
        }

        // A bare `alias foo='claude ...'` with no CLAUDE_CONFIG_DIR is the default profile.
        let bare = #"alias\s+([A-Za-z0-9_-]+)\s*=\s*["']\s*claude(?:\s[^"']*)?["']"#
        let re2 = try? NSRegularExpression(pattern: bare)
        re2?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 2 else { return }
            if map[defaultDir] == nil { map[defaultDir] = ns.substring(with: m.range(at: 1)) }
        }
        return map
    }
}
