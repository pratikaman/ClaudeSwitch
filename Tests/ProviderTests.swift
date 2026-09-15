import Foundation

@main
struct ProviderTests {
    static func main() async throws {
        if CommandLine.arguments.contains("--render") {
            try await MainActor.run { try DesignPreview.render() }
            return
        }
        if CommandLine.arguments.contains("--live-codex") {
            let reading = await CodexClient.shared.reading(home: AIProvider.codex.defaultDir, ttl: 0, force: true)
            print("Codex: signed in=\(reading.credential != nil), usage windows=\(reading.usage.bars.count)")
            if let error = reading.usage.error { print("Status: \(error)") }
            return
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let current = temp.appendingPathComponent("Gauge")
        let legacy = temp.appendingPathComponent("ClaudeSwitch")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyConfig = legacy.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: legacyConfig)
        precondition(Paths.readableFile("config.json", current: current, legacy: legacy) == legacyConfig)
        let currentConfig = current.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: currentConfig)
        precondition(Paths.readableFile("config.json", current: current, legacy: legacy) == currentConfig)
        precondition(FileManager.default.fileExists(atPath: legacyConfig.path))

        let oldPrefs = Data(#"{"defaultCommand":"claude","overrides":{"/example":{"name":"work","hidden":false,"order":2}},"usageTTLSeconds":900}"#.utf8)
        let prefs = try JSONDecoder().decode(Prefs.self, from: oldPrefs)
        precondition(prefs.codexPaths.isEmpty && prefs.grokPaths.isEmpty && prefs.overrides["/example"]?.name == "work")
        precondition(prefs.usageTTLSeconds == 900)
        let roundTrip = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(prefs))
        precondition(roundTrip == prefs)

        var claude = Profile(configDir: "/example/same", isDefault: false, name: "work", command: "claude")
        var codex = claude
        codex.provider = .codex
        codex.command = "codex"
        precondition(claude.id != codex.id && claude.usageKey != codex.usageKey)
        precondition(Launcher.scriptSlug(for: claude) != Launcher.scriptSlug(for: codex))
        precondition(Launcher.environmentLine(for: claude).contains("export CLAUDE_CONFIG_DIR="))
        precondition(Launcher.environmentLine(for: codex).contains("export CODEX_HOME="))
        codex.isDefault = true
        claude.isDefault = true
        precondition(Launcher.environmentLine(for: codex).contains("unset CODEX_HOME"))
        precondition(Launcher.environmentLine(for: claude) == "unset CLAUDE_CONFIG_DIR")
        var grok = codex
        grok.provider = .grok
        precondition(Set([grok.id, codex.id, claude.id]).count == 3)
        precondition(Launcher.environmentLine(for: grok).contains("unset GROK_HOME"))
        grok.isDefault = false
        grok.configDir = "/example/Grok's account"
        precondition(Launcher.environmentLine(for: grok).contains("export GROK_HOME='/example/Grok'\\''s account'"))
        precondition(Launcher.environmentLine(for: grok).contains("unset XAI_API_KEY"))

        for name in [".codex", ".codex-work", ".codex-empty", ".grok", ".grok-work", ".claude-work"] {
            let directory = temp.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if name != ".codex-empty" {
                try Data().write(to: directory.appendingPathComponent("config.toml"))
            }
        }
        let discovered = CLIAccountDiscovery.configDirs(extraPaths: [temp.path + "/.codex/"], home: temp.path,
                                                    environment: ["CODEX_HOME": temp.path + "/.codex-work"])
        precondition(Set(discovered) == Set([temp.path + "/.codex", temp.path + "/.codex-work"]))
        let grokDirs = CLIAccountDiscovery.configDirs(extraPaths: [], provider: .grok, home: temp.path, environment: [:])
        precondition(Set(grokDirs) == Set([temp.path + "/.grok", temp.path + "/.grok-work"]))

        let payload = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":70,"windowDurationMins":10080}},"review":{"limitName":"Code review","primary":{"usedPercent":112,"windowDurationMins":10080}}}}"#.utf8)
        let object = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        let usage = CodexClient.parse(object)
        precondition(usage.error == nil && usage.bars.count == 3)
        precondition(usage.bars.first { $0.kind == "5h" }?.percent == 25)
        precondition(usage.bars.first { $0.kind == "week" }?.percent == 70)
        precondition(usage.bars.first { $0.kind == "review:primary" }?.percent == 112)
        precondition(usage.bars.first?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        let legacyUsage = CodexClient.parse(["rateLimits": ["primary": ["usedPercent": 0, "windowDurationMins": 15]]])
        precondition(legacyUsage.bars.count == 1 && legacyUsage.bars[0].label == "15m")
        precondition(CodexClient.parse([:]).error == "no limit data")
        precondition(CodexClient.parse(["rateLimits": ["primary": ["usedPercent": -1]]]).bars.isEmpty)
        precondition(CodexClient.parse(["rateLimits": ["primary": ["usedPercent": Double.nan]]]).bars.isEmpty)
        precondition(CodexClient.parse(["rateLimits": ["primary": ["usedPercent": Double.greatestFiniteMagnitude]]]).bars.isEmpty)
        precondition(CodexClient.parse(["rateLimits": ["primary": ["usedPercent": true]]]).bars.isEmpty)
        let unknownWindow = CodexClient.parse(["rateLimits": ["secondary": ["usedPercent": 25]]])
        precondition(unknownWindow.bars.first?.label == "secondary")
        print("PASS: preference migration, provider isolation, discovery, and Codex quota parsing")

        let grokUsage = GrokClient.parse(["config": ["creditUsagePercent": 63, "currentPeriod": "WEEKLY",
                                                     "billingCycle": ["end": "2030-01-01T00:00:00Z"]]])
        precondition(grokUsage.error == nil && grokUsage.bars.first?.percent == 63)
        precondition(grokUsage.bars.first?.kind == "week" && grokUsage.bars.first?.resetsAt != nil)
        precondition(GrokClient.parse(["creditUsagePercent": 0]).bars.first?.percent == 0)
        precondition(GrokClient.parse(["creditUsagePercent": 101]).bars.first?.percent == 101)
        precondition(GrokClient.parse(["creditUsagePercent": true]).bars.isEmpty)
        precondition(GrokClient.parse(["creditUsagePercent": -3]).bars.isEmpty)
        precondition(GrokClient.parse(["creditUsagePercent": Double.greatestFiniteMagnitude]).bars.isEmpty)
        precondition(GrokClient.parse(["creditUsagePercent": "unknown"]).bars.isEmpty)
        precondition(GrokClient.parse(["history": [["creditUsagePercent": 10]]]).bars.isEmpty)
        precondition(GrokClient.parse(["monthlyLimit": 100, "onDemandUsed": 50]).bars.isEmpty)
        print("PASS: Grok percentages, explicit billing periods, missing/invalid data, and history exclusion")

        let mock = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/fixtures/codex-rpc.py").path
        let rpc = try UsageRPC(executable: mock, home: temp.path, timeout: 2)
        _ = try rpc.request("initialize", params: [:])
        try rpc.notify("initialized")
        let account = try rpc.request("account/read")
        precondition((account["account"] as? [String: Any])?["email"] as? String == "fixture@example.com")
        let limits = try rpc.request("account/rateLimits/read")
        precondition(CodexClient.parse(limits).bars.first?.percent == 42)
        rpc.close()
        rpc.close()

        let grokRPC = try UsageRPC(executable: mock, home: temp.path, provider: .grok, timeout: 2)
        _ = try grokRPC.request("initialize", params: ["protocolVersion": 1, "clientCapabilities": [:]])
        let grokAuth = try grokRPC.request("_x.ai/auth/check_subscription")
        precondition(grokAuth["authenticated"] as? Bool == true)
        let billing = try grokRPC.request("_x.ai/billing")
        precondition(GrokClient.parse(billing).bars.first?.percent == 37)
        grokRPC.close()

        for mode in ["timeout", "exit", "error"] {
            let connection = try UsageRPC(executable: mock, home: temp.appendingPathComponent(mode).path, timeout: 0.15)
            let start = Date()
            do {
                _ = try connection.request("initialize")
                preconditionFailure("Expected \(mode) to fail")
            } catch let error as UsageRPC.Failure {
                precondition(!error.message.contains("SECRET"))
            }
            connection.close()
            precondition(Date().timeIntervalSince(start) < 3)
        }
        do {
            _ = try UsageRPC(executable: "/nonexistent/codex", home: temp.path)
            preconditionFailure("Expected launch failure")
        } catch is UsageRPC.Failure {}
        print("PASS: RPC handshake, fragmented responses, notifications, timeouts, EOF, and sanitized errors")
    }
}
