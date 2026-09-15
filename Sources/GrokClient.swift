import Foundation

/// Uses Grok Build's own ACP billing extension (verified against CLI 1.0.30).
/// This is a vendor extension rather than a public, versioned billing API.
/// Unknown response shapes fail visibly; they never become a zero-usage bar.
actor GrokClient {
    static let shared = GrokClient()
    private var memo: [String: ProviderReading] = [:]
    private var attemptedAt: [String: Date] = [:]

    func reading(home: String, ttl: TimeInterval, force: Bool) -> ProviderReading {
        if let cached = memo[home], let attempted = attemptedAt[home],
           Date().timeIntervalSince(attempted) < (cached.usage.error == nil && !force ? ttl : 30) {
            return cached
        }
        attemptedAt[home] = Date()
        var reading = ProviderReading(usage: .failed("Install Grok Build CLI to read subscription usage"))
        do {
            guard let executable = AIProvider.grok.executable else { memo[home] = reading; return reading }
            let rpc = try UsageRPC(executable: executable, home: home, provider: .grok)
            defer { rpc.close() }
            _ = try rpc.request("initialize", params: [
                "protocolVersion": 1, "clientCapabilities": [:],
                "clientInfo": ["name": "gauge", "version": "1.0"]
            ])
            let auth = try rpc.request("_x.ai/auth/check_subscription")
            guard auth["authenticated"] as? Bool == true else {
                reading.usage = .failed("Sign in with Grok Build to see subscription usage")
                memo[home] = reading
                return reading
            }
            let meta = auth["meta"] as? [String: Any] ?? [:]
            let tier = meta["subscription_tier"] as? String ?? "Grok"
            reading.account = Account(email: meta["email"] as? String ?? "Grok account",
                                      displayName: "", organizationName: "xAI",
                                      organizationType: tier, organizationRole: "",
                                      accountUuid: meta["user_id"] as? String ?? "")
            reading.credential = Credential(scopes: [], subscriptionType: tier, rateLimitTier: "")
            let billing = try rpc.request("_x.ai/billing")
            reading.usage = Self.parse(billing)
        } catch {
            reading.usage = .failed((error as? UsageRPC.Failure)?.message ?? "Could not read Grok usage")
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

    static func parse(_ result: [String: Any], now: Date = Date()) -> UsageSnapshot {
        // Grok's billing configuration reports creditUsagePercent directly.
        // Do not derive subscription usage from token totals or dollar spend.
        let config = (result["config"] as? [String: Any])
            ?? (result["billingConfig"] as? [String: Any]) ?? result
        guard let percent = usageNumber(config["creditUsagePercent"]), percent >= 0, percent <= 100_000 else {
            return .failed("Grok did not report subscription limits; open its Usage page")
        }
        let cycle = config["billingCycle"] as? [String: Any] ?? [:]
        let period = (config["currentPeriod"] as? String ?? "").uppercased()
        // Only label a period or reset when the service actually provides it.
        let kind = period == "WEEKLY" ? "week" : (period == "MONTHLY" ? "month" : "included")
        var reset: Date?
        if let end = cycle["end"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = formatter.date(from: end) ?? ISO8601DateFormatter().date(from: end)
        }
        return UsageSnapshot(bars: [LimitBar(kind: kind, label: kind, percent: percent,
                                            resetsAt: reset, severity: percent >= 100 ? "critical" : "normal")],
                             fetchedAt: now, error: nil)
    }
}
