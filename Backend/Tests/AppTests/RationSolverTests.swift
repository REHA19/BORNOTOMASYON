import XCTest
@testable import App

/// Placeholder for the golden-test regression suite described in Plan §3 —
/// replay real historical formula inputs/outputs once exported from the iOS app.
final class RationSolverTests: XCTestCase {
    func testSimpleTwoIngredientMix() {
        let ingredients = [
            SolverIngredient(code: "A", name: "A", priceTLPerTon: 1000, minPct: 0, maxPct: 100, nutrients: ["crudeProtein": 20]),
            SolverIngredient(code: "B", name: "B", priceTLPerTon: 2000, minPct: 0, maxPct: 100, nutrients: ["crudeProtein": 40]),
        ]
        let constraints = [SolverConstraint(key: "crudeProtein", minValue: 30, maxValue: nil)]
        let result = RationSolver.solve(ingredients: ingredients, constraints: constraints)

        XCTAssertTrue(result.isFeasible)
        XCTAssertEqual(result.nutrientValues["crudeProtein"] ?? 0, 30, accuracy: 0.5)
    }
}
