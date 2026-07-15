import Testing
@testable import CodexLevelCore

@Suite struct LevelProgressTests {
    private let milestones: [UInt64] = [
        0,
        1_000_000,
        5_000_000,
        10_000_000,
        25_000_000,
        50_000_000,
        100_000_000,
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        5_000_000_000,
        10_000_000_000,
        25_000_000_000,
        50_000_000_000,
        100_000_000_000,
        250_000_000_000,
    ]

    @Test func zeroTokensUsesTheUnlitLevelZeroMilestone() {
        let progress = LevelProgress(lifetimeTokens: 0)

        #expect(progress.level == 0)
        #expect(progress.visualSymbol.isEmpty)
        #expect(progress.currentMilestone == 0)
        #expect(progress.nextMilestone == 1_000_000)
        #expect(progress.percentToNextLevel == 0)
    }

    @Test func everyExactMilestoneSelectsItsLevelAndVisual() {
        for (level, milestone) in milestones.enumerated() {
            let progress = LevelProgress(lifetimeTokens: milestone)

            #expect(progress.level == level)
            #expect(progress.visualSymbol == QQLevelBadges.symbols(for: level))
            #expect(progress.currentMilestone == milestone)
            #expect(progress.nextMilestone == (level == milestones.count - 1 ? nil : milestones[level + 1]))
            #expect(progress.percentToNextLevel == (level == milestones.count - 1 ? 100.0 : 0.0))
        }
    }

    @Test func valueImmediatelyBeforeEveryMilestoneRemainsInThePreviousLevel() {
        for level in 1 ..< milestones.count {
            let tokens = milestones[level] - 1
            let progress = LevelProgress(lifetimeTokens: tokens)
            let lower = milestones[level - 1]
            let upper = milestones[level]
            let expectedPercent = Double(tokens - lower) * 100 / Double(upper - lower)

            #expect(progress.level == level - 1)
            #expect(progress.currentMilestone == lower)
            #expect(progress.nextMilestone == upper)
            #expect(progress.percentToNextLevel == expectedPercent)
        }
    }

    @Test func progressIsLinearBetweenMilestones() {
        let progress = LevelProgress(lifetimeTokens: 3_000_000)

        #expect(progress.level == 1)
        #expect(progress.currentMilestone == 1_000_000)
        #expect(progress.nextMilestone == 5_000_000)
        #expect(progress.percentToNextLevel == 50)
    }

    @Test func progressPreservesFractionalPrecisionBetweenMilestones() {
        let progress = LevelProgress(lifetimeTokens: 1_333_333_333)

        #expect(abs(progress.percentToNextLevel - 33.3333333) < 0.000001)
    }

    @Test func valuesAboveTheHighestMilestoneRemainAtCompletedLevelSixteen() {
        let progress = LevelProgress(lifetimeTokens: .max)

        #expect(progress.level == 16)
        #expect(progress.visualSymbol == "☀️")
        #expect(progress.currentMilestone == 250_000_000_000)
        #expect(progress.nextMilestone == nil)
        #expect(progress.percentToNextLevel == 100)
    }

    @Test(arguments: [
        (0, ""),
        (1, "⭐"),
        (3, "⭐⭐⭐"),
        (4, "🌙"),
        (5, "🌙⭐"),
        (9, "🌙🌙⭐"),
        (11, "🌙🌙⭐⭐⭐"),
        (16, "☀️"),
        (25, "☀️🌙🌙⭐"),
        (64, "👑"),
        (256, "👑👑👑👑"),
    ])
    func decomposesNumericLevelIntoQQStyleBadges(level: Int, expected: String) {
        #expect(QQLevelBadges.symbols(for: level) == expected)
    }
}
