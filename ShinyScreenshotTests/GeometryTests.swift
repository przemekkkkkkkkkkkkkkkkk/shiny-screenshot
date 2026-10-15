import CoreGraphics
import Testing
@testable import ShinyScreenshot

struct GeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let r = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func resizeStopsAtScreenEdge() {
        #expect(resized(r, handle: .se, by: CGSize(width: 2000, height: 2000), in: bounds) == CGRect(x: 100, y: 100, width: 900, height: 700))
    }

    @Test func resizeKeepsMinimumSize() {
        #expect(resized(r, handle: .nw, by: CGSize(width: 500, height: 500), in: bounds) == CGRect(x: 292, y: 192, width: 8, height: 8))
    }

    @Test func edgeHandleMovesOneAxis() {
        #expect(resized(r, handle: .w, by: CGSize(width: -50, height: 30), in: bounds) == CGRect(x: 50, y: 100, width: 250, height: 100))
    }

    @Test func moveStaysOnScreen() {
        #expect(moved(CGRect(x: 900, y: 10, width: 200, height: 100), by: CGSize(width: 50, height: -50), in: bounds)
            == CGRect(x: 800, y: 0, width: 200, height: 100))
    }

    @Test func canvasAddsPaddingAndMatchesRatio() {
        #expect(canvasSize(shot: CGSize(width: 400, height: 200), padding: 50, ratio: nil) == CGSize(width: 500, height: 300))
        #expect(canvasSize(shot: CGSize(width: 400, height: 200), padding: 50, ratio: 1) == CGSize(width: 500, height: 500))
        #expect(canvasSize(shot: CGSize(width: 100, height: 400), padding: 0, ratio: 16.0 / 9) == CGSize(width: 400 * 16.0 / 9, height: 400))
    }
}
