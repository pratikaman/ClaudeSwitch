import Foundation

/// The Anthropic account a config dir is signed into, read from <dir>/.claude.json.
struct Account: Equatable {
    var email: String
    var displayName: String
    var organizationName: String
    var organizationType: String
    var organizationRole: String
    var accountUuid: String

    var planLabel: String {
        switch organizationType {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return organizationType.isEmpty ? "—" : organizationType
        }
    }
}

/// OAuth material for a config dir, read from the macOS keychain.
/// The access token is deliberately not stored on this struct beyond what a
/// single usage request needs — see Keychain.accessToken(for:).
struct Credential: Equatable {
    var expiresAt: Date?
    var refreshExpiresAt: Date?
    var scopes: [String]
    var subscriptionType: String
    var rateLimitTier: String

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    /// "Max 20x" / "Max 5x" / "Pro"
    var tierLabel: String {
        let sub = subscriptionType.capitalized
        if let r = rateLimitTier.range(of: #"(\d+)x"#, options: .regularExpression) {
            return "\(sub) \(rateLimitTier[r])"
        }
        return sub
    }
}

/// One rate-limit window from /api/oauth/usage.
struct LimitBar: Identifiable, Equatable {
    var id: String { kind }
    var kind: String        // "5h", "week", or a scoped label like "Opus"
    var label: String
    var percent: Double     // 0...100
    var resetsAt: Date?
    var severity: String    // normal | warning | critical
}

struct UsageSnapshot: Equatable {
    var bars: [LimitBar]
    var fetchedAt: Date
    var error: String?

    static func failed(_ msg: String) -> UsageSnapshot {
        UsageSnapshot(bars: [], fetchedAt: Date(), error: msg)
    }

    /// What to actually print on a card when there are no bars.
    var friendlyError: String? {
        guard let error else { return nil }
        switch error {
        case "throttled":     return "usage check throttled — back shortly"
        case "not signed in": return "sign in to see limits"
        case "no limit data": return "no limits reported"
        default:              return error
        }
    }
}

/// A Claude Code config directory and everything ClaudeSwitch knows about it.
struct Profile: Identifiable, Equatable {
    var configDir: String              // absolute path
    var isDefault: Bool                // ~/.claude — launched with no CLAUDE_CONFIG_DIR
    var name: String                   // user-facing label
    var account: Account?
    var credential: Credential?
    var alias: String?                 // matching alias found in ~/.zshrc
    var workingDir: String?            // launch cwd override
    var command: String                // what to run in the terminal
    var usage: UsageSnapshot?

    var id: String { configDir }

    /// Keychain service name Claude Code uses for this dir.
    /// The default dir (launched without CLAUDE_CONFIG_DIR) uses the bare name;
    /// every explicit CLAUDE_CONFIG_DIR gets a path-hash suffix.
    var keychainService: String {
        isDefault ? "Claude Code-credentials"
                  : "Claude Code-credentials-\(sha256Prefix8(configDir))"
    }

    var isSignedIn: Bool { credential != nil }

    var shortDir: String { configDir.abbreviatingTilde }

    var subtitle: String {
        if let a = account { return a.email }
        // Claude Code writes the keychain entry before it writes oauthAccount
        // into .claude.json, so briefly there's a token but no identity. Saying
        // "not signed in" next to a plan badge is just wrong.
        return credential != nil ? "signed in" : "not signed in"
    }

    /// A stable per-account accent colour, derived from the config dir path so
    /// it never shuffles between launches (String.hashValue is seeded per run).
    var accentIndex: Int {
        let hex = sha256Prefix8(configDir).prefix(2)
        return (Int(hex, radix: 16) ?? 0) % 5
    }

    var weeklyPercent: Double? {
        usage?.bars.first { $0.kind == "week" }?.percent
    }

    var sessionPercent: Double? {
        usage?.bars.first { $0.kind == "5h" }?.percent
    }

    /// The limit closest to biting — often a model-scoped weekly cap rather
    /// than the overall weekly one.
    var tightestBar: LimitBar? {
        usage?.bars.max { a, b in weight(a) < weight(b) }
    }

    /// The 5-hour window matters less: it refills the same day.
    private func weight(_ b: LimitBar) -> Double {
        b.kind == "5h" ? b.percent * 0.5 : b.percent
    }

    var hasUsageData: Bool { !(usage?.bars.isEmpty ?? true) }

    /// "5h 33% · week 39%" — the windows the headline bar isn't showing.
    var otherBarsSummary: String? {
        guard let bars = usage?.bars, let lead = tightestBar, bars.count > 1 else { return nil }
        let rest = bars.filter { $0.kind != lead.kind }
            .map { "\($0.label) \(Int($0.percent.rounded()))%" }
        return rest.isEmpty ? nil : rest.joined(separator: " · ")
    }

    /// Lower is better. Signed-out profiles, and ones we have no numbers for,
    /// sort last — "unknown" is not the same as "empty".
    var headroomScore: Double {
        guard isSignedIn else { return .infinity }
        guard let bars = usage?.bars, !bars.isEmpty else { return .infinity }
        return bars.map(weight).max() ?? .infinity
    }
}
