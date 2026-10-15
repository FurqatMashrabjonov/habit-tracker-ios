import Testing
import CoreGraphics
@testable import HabitDesign

@Suite struct HeatmapTests {
    /// Stacks ask for an ideal size with an infinite width; that crashed (Int of infinity).
    @Test func geometrySurvivesUnboundedWidth() {
        #expect(FitHeatmap.geometry(width: .infinity, target: 9) == (5, 9))
        #expect(FitHeatmap.geometry(width: 0, target: 9) == (5, 9))
        let (weeks, cell) = FitHeatmap.geometry(width: 320, target: 15)
        #expect(weeks == 17)
        #expect(abs(CGFloat(weeks) * cell * 1.2 - cell * 0.2 - 320) < 0.001)
    }
}
