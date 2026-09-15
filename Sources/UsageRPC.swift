import Foundation
import Darwin

/// A bounded, line-delimited RPC connection. Runs on the provider's actor rather
/// than the UI thread; poll prevents an unresponsive CLI from hanging refresh.
final class UsageRPC {
    struct Failure: Error {
        let message: String
    }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var pending = Data()
    private var nextID = 0
    private var closed = false
    private var started = false
    private let timeout: TimeInterval
    private let provider: AIProvider

    init(executable: String, home: String, provider: AIProvider = .codex, timeout: TimeInterval = 20) throws {
        self.provider = provider
        self.timeout = timeout
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = provider == .grok
            ? ["agent", "--no-leader", "stdio"]
            : ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        for key in claudeSessionMarkers + ["CLAUDE_CONFIG_DIR", "OPENAI_API_KEY", "OPENAI_BASE_URL",
                                           "CODEX_THREAD_ID", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "XAI_API_KEY", "GROK_DEPLOYMENT_KEY"] {
            environment.removeValue(forKey: key)
        }
        environment[provider.environmentKey] = home
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run(); started = true }
        catch { throw Failure(message: "Could not start \(provider.title) CLI") }
        _ = Darwin.fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        // Close the parent's extra pipe ends so EOF is delivered if the CLI exits.
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
    }

    deinit { close() }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        guard started else { return }
        if process.isRunning {
            process.terminate()
            // Bound shutdown even when a subprocess ignores SIGTERM.
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    func notify(_ method: String) throws {
        try send(["method": method, "params": [:]])
    }

    func request(_ method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let line = try readLine(deadline: deadline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            // Decline server requests; this client only reads account metadata.
            if message["method"] != nil, let requestID = message["id"] {
                try send(["id": requestID, "error": ["code": -32601, "message": "Unsupported method"]])
                continue
            }
            guard message["id"] as? Int == id else { continue }
            if message["error"] != nil {
                throw Failure(message: "\(provider.title) could not read usage; check your sign-in or update the CLI")
            }
            guard let result = message["result"] as? [String: Any] else {
                throw Failure(message: "Unexpected \(provider.title) response; update the CLI")
            }
            return result
        }
        throw Failure(message: "\(provider.title) usage check timed out")
    }

    private func send(_ object: [String: Any]) throws {
        var envelope = object
        if provider == .grok { envelope["jsonrpc"] = "2.0" }
        var data = try JSONSerialization.data(withJSONObject: envelope)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw Failure(message: "\(provider.title) connection closed") }
    }

    private func readLine(deadline: Date) throws -> Data {
        while Date() < deadline {
            if let end = pending.firstIndex(of: 10) {
                let line = pending.subdata(in: pending.startIndex..<end)
                pending.removeSubrange(pending.startIndex...end)
                return line
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = max(1, min(1000, Int(deadline.timeIntervalSinceNow * 1000)))
            let ready = Darwin.poll(&descriptor, 1, Int32(remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure(message: "\(provider.title) connection failed")
            }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw Failure(message: "\(provider.title) connection closed; update the CLI") }
            pending.append(contentsOf: bytes.prefix(count))
            guard pending.count <= 2_000_000 else { throw Failure(message: "\(provider.title) response was too large") }
        }
        throw Failure(message: "\(provider.title) usage check timed out")
    }
}
