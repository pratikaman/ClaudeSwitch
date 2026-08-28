import Foundation

/// Reads Claude Code's OAuth material out of the login keychain.
///
/// We shell out to /usr/bin/security rather than calling SecItemCopyMatching
/// directly: the keychain items were created by the `claude` binary and their
/// ACLs already trust the security CLI, so this reads without throwing an
/// authorization prompt at the user on every refresh.
enum Keychain {
    static let servicePrefix = "Claude Code-credentials"
    private static let securityPath = "/usr/bin/security"

    /// Raw JSON blob stored under a service name, or nil if absent/denied.
    private static func blob(forService service: String) -> [String: Any]? {
        let r = run(securityPath, ["find-generic-password", "-s", service, "-w"])
        guard r.ok else { return nil }
        let text = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Non-secret metadata about the sign-in: expiry, scopes, plan tier.
    static func credential(forService service: String) -> Credential? {
        guard let root = blob(forService: service),
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }

        func date(_ key: String) -> Date? {
            guard let ms = oauth[key] as? Double, ms > 0 else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }

        return Credential(
            expiresAt: date("expiresAt"),
            refreshExpiresAt: date("refreshTokenExpiresAt"),
            scopes: oauth["scopes"] as? [String] ?? [],
            subscriptionType: oauth["subscriptionType"] as? String ?? "",
            rateLimitTier: oauth["rateLimitTier"] as? String ?? ""
        )
    }

    /// The bearer token, fetched on demand for a single usage request.
    /// Never cached, never written to disk, never logged.
    static func accessToken(forService service: String) -> String? {
        guard let root = blob(forService: service),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    /// Every "Claude Code-credentials*" service present in the login keychain.
    /// Uses dump-keychain without -d, so it lists attributes only and never
    /// asks for permission to read secrets.
    static func allClaudeServices() -> [String] {
        let r = run(securityPath, ["dump-keychain"], timeout: 30)
        guard r.ok || !r.stdout.isEmpty else { return [] }
        var found = Set<String>()
        for line in r.stdout.split(separator: "\n") {
            guard line.contains("\"svce\"") else { continue }
            guard let start = line.range(of: "=\"") else { continue }
            let rest = line[start.upperBound...]
            guard let end = rest.range(of: "\"", options: .backwards) else { continue }
            let svc = String(rest[..<end.lowerBound])
            if svc.hasPrefix(servicePrefix) { found.insert(svc) }
        }
        return found.sorted()
    }

    /// Permanently removes a credential entry. Used only for orphan cleanup and
    /// profile deletion, both behind an explicit confirmation.
    @discardableResult
    static func delete(service: String) -> Bool {
        run(securityPath, ["delete-generic-password", "-s", service]).ok
    }

    /// The 8-hex suffix of a service name, or nil for the bare default service.
    static func hashSuffix(of service: String) -> String? {
        guard service.hasPrefix(servicePrefix + "-") else { return nil }
        return String(service.dropFirst(servicePrefix.count + 1))
    }
}

/// A credential entry that no longer maps to a config directory on disk.
struct OrphanEntry: Identifiable, Equatable {
    var service: String
    var id: String { service }
    var suffix: String { Keychain.hashSuffix(of: service) ?? "default" }
    var credential: Credential?
}
