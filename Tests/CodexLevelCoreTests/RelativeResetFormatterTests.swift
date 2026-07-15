import Foundation
import Testing
@testable import CodexLevelCore

@Suite struct RelativeResetFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func showsDaysAndHoursWhenMoreThanOneDayRemains() {
        let reset = now.addingTimeInterval((6 * 24 + 20) * 60 * 60 + 59 * 60)

        #expect(RelativeResetFormatter.string(until: reset, now: now) == "Resets in 6d 20h")
    }

    @Test func showsHoursAndMinutesWhenLessThanOneDayRemains() {
        let reset = now.addingTimeInterval((8 * 60 + 42) * 60)

        #expect(RelativeResetFormatter.string(until: reset, now: now) == "Resets in 8h 42m")
    }

    @Test func showsMinutesWhenLessThanOneHourRemains() {
        let reset = now.addingTimeInterval(42 * 60)

        #expect(RelativeResetFormatter.string(until: reset, now: now) == "Resets in 42m")
    }

    @Test func showsPendingWhenTheResetTimeHasPassed() {
        #expect(RelativeResetFormatter.string(until: now, now: now) == "Reset pending")
    }
}
