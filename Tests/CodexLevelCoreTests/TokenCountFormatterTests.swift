import Testing
@testable import CodexLevelCore

@Suite struct TokenCountFormatterTests {
    @Test func formatsBillionScaleTokensWithOneCompactDecimal() {
        #expect(TokenCountFormatter.short(1_502_061_524) == "1.5B tokens")
    }

    @Test func formatsMillionScaleTokensWithOneCompactDecimal() {
        #expect(TokenCountFormatter.short(5_900_000) == "5.9M tokens")
    }

    @Test func keepsSmallTokenCountsExact() {
        #expect(TokenCountFormatter.short(9_999) == "9,999 tokens")
    }
}
