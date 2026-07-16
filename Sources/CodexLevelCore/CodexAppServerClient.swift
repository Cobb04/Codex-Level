import Darwin
import Foundation

public struct WeeklyRateLimit: Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int
    public let resetsAt: Date
    public let plan: CodexPlan?

    public init(
        usedPercent: Double,
        windowDurationMinutes: Int,
        resetsAt: Date,
        plan: CodexPlan? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
        self.plan = plan
    }
}

public struct CodexAppServerClient: Sendable {
    private let codexExecutableURL: URL?
    private let initializeTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let environment: [String: String]

    public init(
        codexExecutableURL: URL? = nil,
        initializeTimeout: TimeInterval = 8,
        requestTimeout: TimeInterval = 5,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.codexExecutableURL = codexExecutableURL
        self.initializeTimeout = initializeTimeout
        self.requestTimeout = requestTimeout
        self.environment = environment
    }

    public func readWeeklyRateLimit() async throws -> WeeklyRateLimit {
        try await Task.detached { [self] in
            try readWeeklyRateLimitSynchronously()
        }.value
    }

    static func parseRateLimitResponse(_ data: Data) throws -> WeeklyRateLimit {
        struct Envelope: Decodable {
            struct Result: Decodable {
                struct RateLimits: Decodable {
                    struct Window: Decodable {
                        let usedPercent: Double
                        let windowDurationMins: Int
                        let resetsAt: TimeInterval
                    }

                    let primary: Window?
                }

                let rateLimits: RateLimits
            }

            let result: Result
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let primary = envelope.result.rateLimits.primary,
              primary.usedPercent.isFinite,
              (0 ... 100).contains(primary.usedPercent),
              primary.windowDurationMins > 0,
              primary.resetsAt > 0
        else {
            throw CodexDataError.responseFormatChanged
        }
        return WeeklyRateLimit(
            usedPercent: primary.usedPercent,
            windowDurationMinutes: primary.windowDurationMins,
            resetsAt: Date(timeIntervalSince1970: primary.resetsAt))
    }

    private func readWeeklyRateLimitSynchronously() throws -> WeeklyRateLimit {
        let executable = try resolvedExecutableURL()
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let inbox = RPCInbox()

        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = environment
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let outputHandle = standardOutput.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                inbox.close()
            } else {
                inbox.append(data)
            }
        }
        let errorHandle = standardError.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw CodexDataError.appServerFailure
        }
        defer {
            Self.stop(
                process: process,
                input: standardInput.fileHandleForWriting,
                output: outputHandle,
                error: errorHandle)
        }

        try send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex_level",
                    "title": "Codex Level",
                    "version": "0.1.0",
                ],
            ],
        ], to: standardInput.fileHandleForWriting)
        let initialization = try inbox.response(id: 1, timeout: initializeTimeout)
        try validateRPCResponse(initialization)

        try send(["method": "initialized", "params": [:]], to: standardInput.fileHandleForWriting)
        try send(["id": 2, "method": "account/rateLimits/read", "params": [:]],
                 to: standardInput.fileHandleForWriting)
        let rateLimitResponse = try inbox.response(id: 2, timeout: requestTimeout)
        try validateRPCResponse(rateLimitResponse)

        guard let data = try? JSONSerialization.data(withJSONObject: rateLimitResponse) else {
            throw CodexDataError.responseFormatChanged
        }
        return try Self.parseRateLimitResponse(data)
    }

    private func resolvedExecutableURL() throws -> URL {
        if let codexExecutableURL {
            guard FileManager.default.isExecutableFile(atPath: codexExecutableURL.path) else {
                throw CodexDataError.codexNotFound
            }
            return codexExecutableURL
        }

        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
        ])
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw CodexDataError.codexNotFound
        }
        return executable
    }

    private func send(_ message: [String: Any], to handle: FileHandle) throws {
        guard JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message)
        else {
            throw CodexDataError.appServerFailure
        }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw CodexDataError.appServerFailure
        }
    }

    private func validateRPCResponse(_ response: [String: Any]) throws {
        guard let rpcError = response["error"] as? [String: Any] else { return }
        let safeMessage = (rpcError["message"] as? String ?? "").lowercased()
        if safeMessage.contains("unauthorized")
            || safeMessage.contains("authentication")
            || safeMessage.contains("401")
            || safeMessage.contains("403")
        {
            throw CodexDataError.authenticationExpired
        }
        throw CodexDataError.appServerFailure
    }

    private static func stop(
        process: Process,
        input: FileHandle,
        output: FileHandle,
        error: FileHandle
    ) {
        try? input.close()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(0.2)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        output.readabilityHandler = nil
        error.readabilityHandler = nil
        try? output.close()
        try? error.close()
    }

}

private final class RPCInbox: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var messages: [[String: Any]] = []
    private var isClosed = false

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var addedCount = 0
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                messages.append(object)
                addedCount += 1
            }
        }
        lock.unlock()
        for _ in 0 ..< addedCount { signal.signal() }
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
        signal.signal()
    }

    func response(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            if let index = messages.firstIndex(where: { ($0["id"] as? NSNumber)?.intValue == id }) {
                let message = messages.remove(at: index)
                lock.unlock()
                return message
            }
            let closed = isClosed
            lock.unlock()

            if closed { throw CodexDataError.appServerFailure }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0,
                  signal.wait(timeout: .now() + remaining) == .success
            else {
                throw CodexDataError.appServerTimeout
            }
        }
    }
}
