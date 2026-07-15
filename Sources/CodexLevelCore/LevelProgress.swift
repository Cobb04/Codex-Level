public struct LevelProgress: Equatable, Sendable {
    private static let milestones: [UInt64] = [
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

    public let level: Int
    public let visualSymbol: String
    public let currentMilestone: UInt64
    public let nextMilestone: UInt64?
    public let percentToNextLevel: Double

    public init(lifetimeTokens: UInt64) {
        let level = Self.milestones.lastIndex { $0 <= lifetimeTokens } ?? 0
        let current = Self.milestones[level]

        self.level = level
        visualSymbol = QQLevelBadges.symbols(for: level)
        currentMilestone = current

        guard level < Self.milestones.count - 1 else {
            nextMilestone = nil
            percentToNextLevel = 100
            return
        }

        let next = Self.milestones[level + 1]
        nextMilestone = next
        percentToNextLevel = Double(lifetimeTokens - current) * 100 / Double(next - current)
    }
}
