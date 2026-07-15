import Foundation
import Testing
@testable import CodexLevelCore

@Suite(.serialized) struct CodexAppServerClientTests {
    @Test func parsesPrimaryWindowWhenSecondaryIsNull() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":37.5,"windowDurationMins":10080,"resetsAt":1784217600},"secondary":null}}}"#.utf8)

        let limit = try CodexAppServerClient.parseRateLimitResponse(data)

        #expect(limit.usedPercent == 37.5)
        #expect(limit.windowDurationMinutes == 10_080)
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_784_217_600))
    }

    @Test func missingPrimaryWindowIsAFormatChange() {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null}}}"#.utf8)

        #expect(throws: CodexDataError.responseFormatChanged) {
            try CodexAppServerClient.parseRateLimitResponse(data)
        }
    }

    @Test func performsInitializeHandshakeAndReadsRateLimit() async throws {
        let executable = try temporaryExecutable(contents: """
            #!/bin/sh
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{"userAgent":"fixture"}}'
            IFS= read -r initialized
            IFS= read -r rate_limits
            printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1784217600},"secondary":null}}}'
            """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        let client = CodexAppServerClient(
            codexExecutableURL: executable,
            initializeTimeout: 1,
            requestTimeout: 1)
        let limit = try await client.readWeeklyRateLimit()

        #expect(limit.usedPercent == 42)
        #expect(limit.windowDurationMinutes == 10_080)
    }

    @Test func missingExecutableMeansCodexNotFound() async {
        let client = CodexAppServerClient(
            codexExecutableURL: URL(fileURLWithPath: "/tmp/codex-level-missing-\(UUID().uuidString)"),
            initializeTimeout: 0.1,
            requestTimeout: 0.1)

        await #expect(throws: CodexDataError.codexNotFound) {
            try await client.readWeeklyRateLimit()
        }
    }

    @Test func silentAppServerTimesOutPromptly() async throws {
        let executable = try temporaryExecutable(contents: """
            #!/bin/sh
            trap 'exit 0' TERM
            while :; do :; done
            """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let client = CodexAppServerClient(
            codexExecutableURL: executable,
            initializeTimeout: 0.05,
            requestTimeout: 0.05)
        let clock = ContinuousClock()
        let started = clock.now

        await #expect(throws: CodexDataError.appServerTimeout) {
            try await client.readWeeklyRateLimit()
        }

        #expect(started.duration(to: clock.now) < .seconds(1))
    }

    @Test func rateLimitRequestTimesOutAfterSuccessfulInitialization() async throws {
        let executable = try temporaryExecutable(contents: """
            #!/bin/sh
            trap 'exit 0' TERM
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{"userAgent":"fixture"}}'
            while :; do :; done
            """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let client = CodexAppServerClient(
            codexExecutableURL: executable,
            initializeTimeout: 1,
            requestTimeout: 0.05)

        await #expect(throws: CodexDataError.appServerTimeout) {
            try await client.readWeeklyRateLimit()
        }
    }

    private func temporaryExecutable(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-level-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex", isDirectory: false)
        try Data(contents.utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: executable.path)
        return executable
    }
}
