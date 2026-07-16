import AppKit
import Testing
@testable import CodexLevelApp
@testable import CodexLevelCore

@Suite struct PlanDiamondStyleTests {
    @Test(arguments: [
        (CodexPlan.go, "plan-diamond-go"),
        (CodexPlan.plus, "plan-diamond-plus"),
        (CodexPlan.pro5x, "plan-diamond-pro5x"),
        (CodexPlan.pro20x, "plan-diamond-pro20x"),
    ])
    func suppliedArtworkHasOneExactAssetPerPlan(plan: CodexPlan, expected: String) {
        #expect(PlanDiamondAsset.resourceName(for: plan) == expected)
        #expect(PlanDiamondAsset.resourceURL(for: plan) != nil)
    }

    @Test(arguments: [
        CodexPlan.go,
        CodexPlan.plus,
        CodexPlan.pro5x,
        CodexPlan.pro20x,
    ])
    func suppliedArtworkHasTransparentCorners(plan: CodexPlan) throws {
        let url = try #require(PlanDiamondAsset.resourceURL(for: plan))
        let data = try Data(contentsOf: url)
        let bitmap = try #require(NSBitmapImageRep(data: data))

        #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: 0)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)?.alphaComponent == 0)
        #expect(
            bitmap.colorAt(
                x: bitmap.pixelsWide - 1,
                y: bitmap.pixelsHigh - 1)?.alphaComponent == 0)
    }
}
