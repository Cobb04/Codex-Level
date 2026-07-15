import Foundation

public enum RelativeResetFormatter {
    public static func string(until reset: Date, now: Date = Date()) -> String {
        let totalMinutes = Int(reset.timeIntervalSince(now) / 60)
        guard totalMinutes > 0 else { return "Reset pending" }

        let totalHours = totalMinutes / 60
        if totalHours >= 24 {
            return "Resets in \(totalHours / 24)d \(totalHours % 24)h"
        }
        if totalHours > 0 {
            return "Resets in \(totalHours)h \(totalMinutes % 60)m"
        }
        return "Resets in \(totalMinutes)m"
    }
}
