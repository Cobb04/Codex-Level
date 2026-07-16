import Testing
@testable import CodexLevelCore

@Suite struct CodexPlanTests {
    @Test(arguments: [
        ("go", CodexPlan.go),
        ("plus", CodexPlan.plus),
        ("prolite", CodexPlan.pro5x),
        ("pro_lite", CodexPlan.pro5x),
        ("pro-lite", CodexPlan.pro5x),
        ("pro", CodexPlan.pro20x),
    ])
    func mapsServerPlanTypesToCodexLevelPlans(rawValue: String, expected: CodexPlan) {
        #expect(CodexPlan(serverValue: rawValue) == expected)
    }

    @Test func unknownPlanTypeIsNotGuessed() {
        #expect(CodexPlan(serverValue: "enterprise") == nil)
        #expect(CodexPlan(serverValue: nil) == nil)
    }
}
