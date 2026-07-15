import Foundation
import Testing
@testable import CodexLevelApp
import CodexLevelCore

@Suite struct CodexLevelViewModelTests {
    @MainActor
    @Test func refreshFailureKeepsLastSuccessfulProfileAndWeeklyUsage() async {
        let profiles = ResultQueue(values: [
            LoadState.value(CodexProfile(lifetimeTokens: 1_500_000_000, currentStreakDays: 6)),
            LoadState.failure(.networkFailure),
        ])
        let weeklyLimits = ResultQueue(values: [
            LoadState.value(WeeklyRateLimit(
                usedPercent: 48,
                windowDurationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))),
            LoadState.failure(.networkFailure),
        ])
        let model = CodexLevelViewModel(
            profileLoader: { await profiles.next() },
            weeklyLimitLoader: { await weeklyLimits.next() },
            startsAutomatically: false)

        await model.refresh()
        await model.refresh()

        guard case let .value(profile) = model.profile else {
            Issue.record("Expected the last successful Profile value")
            return
        }
        guard case let .value(weeklyLimit) = model.weeklyLimit else {
            Issue.record("Expected the last successful Weekly value")
            return
        }
        #expect(profile.lifetimeTokens == 1_500_000_000)
        #expect(weeklyLimit.usedPercent == 48)
    }
}

private actor ResultQueue<Value: Sendable> {
    private var values: [Value]

    init(values: [Value]) {
        self.values = values
    }

    func next() -> Value {
        values.removeFirst()
    }
}
