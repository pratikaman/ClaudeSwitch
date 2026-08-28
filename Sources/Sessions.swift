import Foundation

/// A resumable Claude Code conversation belonging to one config dir.
struct RecentSession: Identifiable, Equatable {
    var sessionID: String
    var cwd: String
    var title: String
    var modified: Date

    var id: String { sessionID }
    var projectName: String { (cwd as NSString).lastPathComponent }
    var shortCwd: String { cwd.abbreviatingTilde }
}

enum Sessions {
    /// The most recent conversations for a config dir.
    ///
    /// Transcripts live at `<dir>/projects/<encoded-path>/<session-uuid>.jsonl`.
    /// That folder name is a *lossy* encoding — both `/` and `-` become `-`, so
    /// `bihar-orchestra` and `bihar/orchestra` are indistinguishable. The real
    /// working directory is therefore read out of the transcript itself.
    static func recent(in configDir: String, limit: Int = 5) -> [RecentSession] {
        let fm = FileManager.default
        let projects = configDir + "/projects"
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects) else { return [] }

        // Rank every transcript by mtime before parsing any of them, so we only
        // open the handful we're actually going to show.
        var candidates: [(path: String, date: Date)] = []
        for dir in dirs {
            let full = projects + "/" + dir
            guard let files = try? fm.contentsOfDirectory(atPath: full) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = full + "/" + file
                let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                candidates.append((path, date ?? .distantPast))
            }
        }
        candidates.sort { $0.date > $1.date }

        var out: [RecentSession] = []
        for candidate in candidates.prefix(limit * 4) {
            guard let session = parse(path: candidate.path, modified: candidate.date) else { continue }
            // One entry per working directory — ten sessions in the same repo
            // isn't a useful menu.
            if out.contains(where: { $0.cwd == session.cwd }) { continue }
            out.append(session)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Parsing

    private static let chunk = 256 * 1024

    /// Reads `cwd` from the head of the transcript and the newest `ai-title`
    /// from its tail, rather than parsing megabytes of conversation in between.
    private static func parse(path: String, modified: Date) -> RecentSession? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let sessionID = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !sessionID.isEmpty else { return nil }

        let head = (try? handle.read(upToCount: chunk)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        var tail = Data()
        if size > UInt64(chunk) {
            try? handle.seek(toOffset: size - UInt64(chunk))
            tail = (try? handle.readToEnd()) ?? Data()
        }

        var cwd: String?
        var title: String?
        var lastPrompt: String?
        var firstUserText: String?

        for record in records(in: head) {
            if cwd == nil, let v = record["cwd"] as? String, !v.isEmpty { cwd = v }
            if let t = record["aiTitle"] as? String, !t.isEmpty { title = t }
            if firstUserText == nil, record["type"] as? String == "user" {
                firstUserText = userText(record)
            }
            if let p = record["lastPrompt"] as? String, !p.isEmpty { lastPrompt = p }
        }
        // The tail holds the most recent title, which is the best label.
        for record in records(in: tail) {
            if let t = record["aiTitle"] as? String, !t.isEmpty { title = t }
            if let p = record["lastPrompt"] as? String, !p.isEmpty { lastPrompt = p }
            if cwd == nil, let v = record["cwd"] as? String, !v.isEmpty { cwd = v }
        }

        guard let cwd, FileManager.default.fileExists(atPath: cwd) else { return nil }

        // Prefer the generated title. A raw prompt is a poor label — sessions
        // whose first input was "c" or a slash command produced titles like
        // "c" and "<command-message>init</command-message>" — so anything that
        // cleans up to almost nothing falls through to the folder name.
        let label = clean(title) ?? clean(lastPrompt) ?? clean(firstUserText)
            ?? (cwd as NSString).lastPathComponent
        return RecentSession(sessionID: sessionID, cwd: cwd, title: label, modified: modified)
    }

    /// JSONL records in a chunk. A chunk boundary can slice a line in half; that
    /// fragment simply fails to decode and is dropped.
    private static func records(in data: Data) -> [[String: Any]] {
        data.split(separator: UInt8(ascii: "\n")).compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
        }
    }

    private static func userText(_ record: [String: Any]) -> String? {
        guard let message = record["message"] as? [String: Any] else { return nil }
        if let s = message["content"] as? String { return s }
        if let parts = message["content"] as? [[String: Any]] {
            for part in parts where part["type"] as? String == "text" {
                if let t = part["text"] as? String { return t }
            }
        }
        return nil
    }

    /// Normalises a candidate label, or returns nil if there's nothing useful
    /// left — slash commands arrive wrapped in XML-ish tags, and a stray
    /// keystroke is not a session title.
    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var s = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 4 else { return nil }
        return s.count > 52 ? String(s.prefix(51)) + "…" : s
    }
}
