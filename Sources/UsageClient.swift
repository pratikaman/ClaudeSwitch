import Foundation

/// Fetches rate-limit usage from Anthropic's OAuth usage endpoint.
///
/// The endpoint rate-limits aggressively, so results are cached on disk and
/// shared across launches. A 429 keeps the last good snapshot rather than
/// blanking the menu.
actor UsageClient {
    static let shared = UsageClient()

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var memo: [String: UsageSnapshot] = [:]      // keychain service -> snapshot
    private var cooldownUntil: [String: Date] = [:]     // service -> don't call before

    /// The usage endpoint limits per account, and a 429 sticks for minutes.
    /// Backing off keeps a throttled account from being re-hammered — and
    /// blanked — on every menu open once the normal TTL lapses.
    private static let cooldown: TimeInterval = 15 * 60

    private var cacheURL: URL {
        Paths.support.appendingPathComponent("usage-cache.json")
    }

    private var loaded = false

    /// The disk cache is read on first use rather than in init, so the actor's
    /// isolation is respected under Swift 6 concurrency.
    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        loadCache()
    }

    /// Returns a snapshot, refetching only if the cached one is older than `ttl`.
    func usage(forService service: String, ttl: TimeInterval, force: Bool = false) async -> UsageSnapshot? {
        ensureLoaded()
        if !force, let cached = memo[service],
           Date().timeIntervalSince(cached.fetchedAt) < ttl, cached.error == nil {
            return cached
        }
        // Honour an active backoff regardless of TTL or an explicit refresh.
        if let until = cooldownUntil[service], Date() < until {
            return memo[service] ?? .failed("throttled")
        }

        guard let token = Keychain.accessToken(forService: service) else {
            let snap = UsageSnapshot.failed("not signed in")
            memo[service] = snap
            return snap
        }

        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

            if code == 429 {
                cooldownUntil[service] = Date().addingTimeInterval(Self.cooldown)
                // Keep whatever we last knew; just mark it stale.
                if var last = memo[service], !last.bars.isEmpty {
                    last.error = "throttled — showing last known"
                    memo[service] = last
                    return last
                }
                let snap = UsageSnapshot.failed("throttled")
                memo[service] = snap
                return snap
            }
            guard code == 200 else {
                let snap = UsageSnapshot.failed("HTTP \(code)")
                memo[service] = snap
                return snap
            }

            let snap = Self.parse(data)
            memo[service] = snap
            saveCache()
            return snap
        } catch {
            let snap = UsageSnapshot.failed(error.localizedDescription)
            memo[service] = snap
            return snap
        }
    }

    /// Whether the next `usage(forService:)` would actually hit the network.
    /// Lets the caller pace its requests instead of tripping the rate limiter.
    func needsFetch(forService service: String, ttl: TimeInterval, force: Bool) -> Bool {
        ensureLoaded()
        if let until = cooldownUntil[service], Date() < until { return false }
        if force { return true }
        guard let cached = memo[service], cached.error == nil else { return true }
        return Date().timeIntervalSince(cached.fetchedAt) >= ttl
    }

    func cached(forService service: String) -> UsageSnapshot? {
        ensureLoaded()
        return memo[service]
    }

    // MARK: - Parsing

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ any: Any?) -> Date? {
        if let s = any as? String {
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        if let n = any as? Double { return Date(timeIntervalSince1970: n) }
        return nil
    }

    static func parse(_ data: Data) -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed("bad response")
        }
        if let err = root["error"] as? [String: Any] {
            return .failed(err["message"] as? String ?? "error")
        }

        var bars: [LimitBar] = []

        // Preferred shape: a normalized `limits` array.
        if let limits = root["limits"] as? [[String: Any]] {
            for l in limits {
                let kind = l["kind"] as? String ?? ""
                let pct = (l["percent"] as? Double) ?? 0
                let reset = date(l["resets_at"])
                let sev = l["severity"] as? String ?? "normal"
                switch kind {
                case "session", "five_hour":
                    bars.append(LimitBar(kind: "5h", label: "5h", percent: pct,
                                         resetsAt: reset, severity: sev))
                case "weekly_all", "seven_day":
                    bars.append(LimitBar(kind: "week", label: "week", percent: pct,
                                         resetsAt: reset, severity: sev))
                default:
                    // `scope` is an object: {model: {display_name: "Fable"}, surface: ...}
                    // Reading it as a String silently produced labels like
                    // "Weekly_Scoped" instead of the model name.
                    var label = ""
                    if let scope = l["scope"] as? [String: Any] {
                        if let model = scope["model"] as? [String: Any],
                           let name = model["display_name"] as? String, !name.isEmpty {
                            label = name
                        } else if let surface = scope["surface"] as? String, !surface.isEmpty {
                            label = surface
                        }
                    }
                    if label.isEmpty {
                        label = kind.replacingOccurrences(of: "_", with: " ")
                    }
                    guard !label.isEmpty else { continue }
                    bars.append(LimitBar(kind: label.lowercased(), label: label, percent: pct,
                                         resetsAt: reset, severity: sev))
                }
            }
        }

        // Fallback / supplement: the legacy per-window objects.
        func legacy(_ key: String, _ kind: String, _ label: String) {
            guard bars.first(where: { $0.kind == kind }) == nil,
                  let o = root[key] as? [String: Any],
                  let util = o["utilization"] as? Double else { return }
            bars.append(LimitBar(kind: kind, label: label, percent: util,
                                 resetsAt: date(o["resets_at"]), severity: "normal"))
        }
        legacy("five_hour", "5h", "5h")
        legacy("seven_day", "week", "week")
        legacy("seven_day_opus", "Opus", "Opus wk")
        legacy("seven_day_sonnet", "Sonnet", "Sonnet wk")

        let order = ["5h": 0, "week": 1]
        bars.sort { (order[$0.kind] ?? 9, $0.kind) < (order[$1.kind] ?? 9, $1.kind) }

        return UsageSnapshot(bars: bars, fetchedAt: Date(), error: bars.isEmpty ? "no limit data" : nil)
    }

    // MARK: - Disk cache

    private struct CacheRow: Codable {
        var service: String, kind: String, label: String, percent: Double
        var resetsAt: Date?, severity: String, fetchedAt: Date
    }

    private func saveCache() {
        var rows: [CacheRow] = []
        for (svc, snap) in memo where snap.error == nil {
            for b in snap.bars {
                rows.append(CacheRow(service: svc, kind: b.kind, label: b.label,
                                     percent: b.percent, resetsAt: b.resetsAt,
                                     severity: b.severity, fetchedAt: snap.fetchedAt))
            }
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let rows = try? JSONDecoder().decode([CacheRow].self, from: data) else { return }
        for row in rows {
            var snap = memo[row.service] ?? UsageSnapshot(bars: [], fetchedAt: row.fetchedAt, error: nil)
            snap.bars.append(LimitBar(kind: row.kind, label: row.label, percent: row.percent,
                                      resetsAt: row.resetsAt, severity: row.severity))
            snap.fetchedAt = row.fetchedAt
            memo[row.service] = snap
        }
    }
}
