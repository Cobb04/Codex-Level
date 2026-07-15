public enum QQLevelBadges {
    public static func symbols(for level: Int) -> String {
        var remainder = min(max(level, 0), 256)
        let crowns = remainder / 64
        remainder %= 64
        let suns = remainder / 16
        remainder %= 16
        let moons = remainder / 4
        let stars = remainder % 4

        return String(repeating: "👑", count: crowns)
            + String(repeating: "☀️", count: suns)
            + String(repeating: "🌙", count: moons)
            + String(repeating: "⭐", count: stars)
    }
}
