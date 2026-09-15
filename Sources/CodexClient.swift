import Foundation

struct ProviderReading {
    var account: Account?
    var credential: Credential?
    var usage: UsageSnapshot
}

/// Uses the documented account/read and account/rateLimits/read protocol.
/// No prompts, threads, or inference requests are created.
actor CodexClient {
    static let shared = CodexClient()
    private var memo: [String: ProviderReading] = [:]
    private var attemptedAt: [String: Date] = [:]

    func reading(home: String, ttl: TimeInterval, force: Bool) -> ProviderReading {
        // A short failure cooldown also applies to the Refresh button.
        if let cached = memo[home], let attempted = attemptedAt[home],
           Date().timeIntervalSince(attempted) < (cached.usage.error == nil && !force ? ttl : 30) {
            return cached
        }
        attemptedAt[home] = Date()
        var reading = ProviderReading(usage: .failed("Install Codex CLI to read usage"))
        do {
            guard let executable = Self.executable else { memo[home] = reading; return reading }
            let rpc = try UsageRPC(executable: executable, home: home)
            defer { rpc.close() }
            _ = try rpc.request("initialize", params: [
                "clientInfo": ["name": "gauge", "version": "1.0"],
                "capabilities": ["experimentalApi": false]
            ])
            try rpc.notify("initialized")
            let identity = try rpc.request("account/read", params: ["refreshToken": false])
            guard let account = identity["account"] as? [String: Any] else {
                reading.usage = .failed("Sign in with Codex to see limits")
                memo[home] = reading
                return reading
            }
            let type = account["type"] as? String ?? ""
            let plan = account["planType"] as? String ?? ""
            reading.account = Account(email: account["email"] as? String ?? "Codex account",
                                      displayName: "", organizationName: "OpenAI",
                                      organizationType: plan, organizationRole: "", accountUuid: "")
            reading.credential = Credential(scopes: [], subscriptionType: plan.isEmpty ? type : plan,
                                            rateLimitTier: "")
            guard type == "chatgpt" else {
                reading.usage = .failed("Subscription limits require a ChatGPT sign-in")
                memo[home] = reading
                return reading
            }
            let limits = try rpc.request("account/rateLimits/read")
            reading.account?.accountUuid = limits["accountId"] as? String ?? ""
            reading.usage = Self.parse(limits)
        } catch {
            // RPC error messages can contain remote payloads. Show only our own
            // diagnostics and never forward stderr or authentication material.
            reading.usage = .failed((error as? UsageRPC.Failure)?.message ?? "Could not read Codex usage")
            if let cached = memo[home] {
                reading.account = reading.account ?? cached.account
                reading.credential = reading.credential ?? cached.credential
                if !cached.usage.bars.isEmpty {
                    reading.usage.bars = cached.usage.bars
                    reading.usage.fetchedAt = cached.usage.fetchedAt
                }
            }
        }
        memo[home] = reading
        return reading
    }

    static var executable: String? { AIProvider.codex.executable }

    static func parse(_ result: [String: Any], now: Date = Date()) -> UsageSnapshot {
        var buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]] ?? [:]
        if buckets.isEmpty, let legacy = result["rateLimits"] as? [String: Any] {
            buckets[legacy["limitId"] as? String ?? "codex"] = legacy
        }
        var bars: [LimitBar] = []
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key] else { continue }
            for windowKey in ["primary", "secondary"] {
                guard let window = bucket[windowKey] as? [String: Any],
                      let percent = usageNumber(window["usedPercent"]),
                      percent >= 0, percent <= 100_000 else { continue }
                let minutes = window["windowDurationMins"] as? Int
                let duration: String
                switch minutes {
                case 10080: duration = "week"
                case let value? where value > 0 && value % 1440 == 0: duration = "\(value / 1440)d"
                case let value? where value > 0 && value % 60 == 0: duration = "\(value / 60)h"
                case let value? where value > 0: duration = "\(value)m"
                default: duration = windowKey
                }
                let canonical = key == "codex" && ["5h", "week"].contains(duration)
                let kind = canonical ? duration : "\(key):\(windowKey)"
                let name = bucket["limitName"] as? String ?? key
                let label = key == "codex" ? duration : "\(name) · \(duration)"
                let reset = (window["resetsAt"] as? Double).flatMap {
                    $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
                }
                // Some quota buckets can exceed 100%; retain that information.
                bars.append(LimitBar(kind: kind, label: label, percent: percent, resetsAt: reset,
                                     severity: percent >= 100 ? "critical" : "normal"))
            }
        }
        return UsageSnapshot(bars: bars, fetchedAt: now, error: bars.isEmpty ? "no limit data" : nil)
    }
}
