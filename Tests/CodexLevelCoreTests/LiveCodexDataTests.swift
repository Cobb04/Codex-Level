import Foundation
import Testing
@testable import CodexLevelCore

@Suite struct LiveCodexDataTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["CODEX_LEVEL_RUN_LIVE_TESTS"] == "1",
        "Requires explicit access to the local Codex login and network."))
    func readsLocalProfile() async throws {
        let credentials = try CodexCredentials.load()
        let profile = try await CodexProfileClient().fetchProfile(credentials: credentials)

        #expect(profile.preferredName != nil)
        #expect(profile.lifetimeTokens > 0)
        #expect(profile.currentStreakDays != nil)
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["CODEX_LEVEL_RUN_LIVE_TESTS"] == "1",
        "Requires explicit access to the local Codex login and network."))
    func readsLocalWeeklyLimit() async throws {
        let credentials = try CodexCredentials.load()
        let weeklyLimit = try await CodexOAuthUsageClient().readWeeklyRateLimit(credentials: credentials)
        #expect(weeklyLimit.usedPercent.isFinite)
        #expect((0 ... 100).contains(weeklyLimit.usedPercent))
        #expect(weeklyLimit.windowDurationMinutes > 0)
        #expect(weeklyLimit.resetsAt.timeIntervalSince1970 > 0)
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["CODEX_LEVEL_RUN_LIVE_TESTS"] == "1",
        "Requires explicit access to the local Codex login and network."))
    func readsLocalResetCredits() async throws {
        let credentials = try CodexCredentials.load()
        let now = Date()
        let credits = try await CodexResetCreditsClient()
            .fetchAvailableCredits(credentials: credentials, now: now)

        #expect(credits.allSatisfy { !$0.id.isEmpty })
        #expect(credits.allSatisfy { $0.expiresAt.map { $0 > now } ?? true })
    }

}
