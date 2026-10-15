import CoreGraphics
import Testing
@testable import ShinyScreenshot

/// Randomised invariants for the pure geometry in Geometry.swift.
struct GeometryFuzzTests {
    static let iterations = 50_000

    func randomBounds(_ rng: inout SplitMix64) -> CGRect {
        CGRect(x: .random(in: -4000...4000, using: &rng), y: .random(in: -4000...4000, using: &rng),
               width: .random(in: 100...6016, using: &rng), height: .random(in: 100...3384, using: &rng))
    }

    /// A rect inside `b` with sides of at least `minSide`.
    func randomRect(in b: CGRect, minSide: CGFloat, _ rng: inout SplitMix64) -> CGRect {
        let w = CGFloat.random(in: minSide...b.width, using: &rng), h = CGFloat.random(in: minSide...b.height, using: &rng)
        return CGRect(x: .random(in: b.minX...b.maxX - w, using: &rng), y: .random(in: b.minY...b.maxY - h, using: &rng), width: w, height: h)
    }

    func randomDelta(_ rng: inout SplitMix64) -> CGSize {
        Bool.random(using: &rng)
            ? CGSize(width: .random(in: -20...20, using: &rng), height: .random(in: -20...20, using: &rng))
            : CGSize(width: .random(in: -10_000...10_000, using: &rng), height: .random(in: -10_000...10_000, using: &rng))
    }

    func isSane(_ r: CGRect) -> Bool {
        r.minX.isFinite && r.minY.isFinite && r.width.isFinite && r.height.isFinite && r.width >= 0 && r.height >= 0
    }

    @Test func rectFromTwoPointsIsNormalised() {
        var rng = SplitMix64(state: 1)
        for _ in 0..<Self.iterations {
            let a = pt(.random(in: -1e4...1e4, using: &rng), .random(in: -1e4...1e4, using: &rng))
            let b = pt(.random(in: -1e4...1e4, using: &rng), .random(in: -1e4...1e4, using: &rng))
            let r = rect(from: a, to: b)
            #expect(isSane(r))
            #expect(r.minX == min(a.x, b.x) && abs(r.maxY - max(a.y, b.y)) < 1e-6)
        }
    }

    @Test func movedKeepsSizeAndStaysInside() {
        var rng = SplitMix64(state: 2)
        for _ in 0..<Self.iterations {
            let b = randomBounds(&rng), r = randomRect(in: b, minSide: 0, &rng), d = randomDelta(&rng)
            let m = moved(r, by: d, in: b)
            #expect(m.size == r.size)
            #expect(b.insetBy(dx: -1e-6, dy: -1e-6).contains(m), "\(r) by \(d) in \(b) → \(m)")
        }
    }

    @Test func resizedStaysInsideAndKeepsTheMinimumSide() {
        var rng = SplitMix64(state: 3)
        for _ in 0..<Self.iterations {
            let b = randomBounds(&rng), r = randomRect(in: b, minSide: 8, &rng), d = randomDelta(&rng)
            let h = Handle.allCases.randomElement(using: &rng)!
            let n = resized(r, handle: h, by: d, in: b)
            let label = "\(h) \(r) by \(d) in \(b) → \(n)"
            #expect(isSane(n), "\(label)")
            #expect(b.insetBy(dx: -1e-6, dy: -1e-6).contains(n), "\(label)")
            #expect(n.width >= 8 - 1e-9 && n.height >= 8 - 1e-9, "\(label)")
            // Edges the handle does not own stay put.
            if [.n, .s].contains(h) { #expect(n.minX == r.minX && n.maxX == r.maxX, "\(label)") }
            if [.e, .w].contains(h) { #expect(n.minY == r.minY && n.maxY == r.maxY, "\(label)") }
            if [.ne, .e, .se, .n, .s].contains(h) { #expect(abs(n.minX - r.minX) < 1e-9, "\(label)") }
            if [.sw, .s, .se, .e, .w].contains(h) { #expect(abs(n.minY - r.minY) < 1e-9, "\(label)") }
        }
    }

    @Test func resizedSmallRectNearAnEdgeStaysInside() {
        let b = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(b.contains(resized(CGRect(x: 0, y: 0, width: 5, height: 5), handle: .nw, by: .zero, in: b)))   // (-3, -3, 8, 8)
    
        var rng = SplitMix64(state: 4)
        var escaped = 0
        for _ in 0..<Self.iterations {
            let side = CGFloat.random(in: 0.5..<8, using: &rng)
            let r = CGRect(x: Bool.random(using: &rng) ? 0 : b.maxX - side, y: Bool.random(using: &rng) ? 0 : b.maxY - side, width: side, height: side)
            let n = resized(r, handle: Handle.allCases.randomElement(using: &rng)!, by: randomDelta(&rng), in: b)
            #expect(isSane(n))
            if !b.insetBy(dx: -1e-6, dy: -1e-6).contains(n) { escaped += 1 }
        }
        print("FUZZ resized: \(escaped) of \(Self.iterations) sub-8pt edge rects escaped the bounds")
        #expect(escaped == 0)
    }

    @Test func canvasSizeHonoursPaddingAndRatio() {
        var rng = SplitMix64(state: 5)
        let ratios = Ratio.allCases.map(\.value)
        for _ in 0..<Self.iterations {
            let shot = CGSize(width: .random(in: 0...10_000, using: &rng), height: .random(in: 0...10_000, using: &rng))
            let p = CGFloat.random(in: 0...500, using: &rng), ratio = ratios.randomElement(using: &rng)!
            let c = canvasSize(shot: shot, padding: p, ratio: ratio)
            let label = "\(shot) p\(p) r\(String(describing: ratio)) → \(c)"
            #expect(c.width.isFinite && c.height.isFinite, "\(label)")
            #expect(c.width >= shot.width + 2 * p - 1e-6 && c.height >= shot.height + 2 * p - 1e-6, "\(label)")
            if let ratio, c.height > 0 { #expect(abs(c.width / c.height - ratio) < 1e-9, "\(label)") }
        }
        // Degenerate: nothing selected and no padding.
        for ratio in ratios {
            let c = canvasSize(shot: .zero, padding: 0, ratio: ratio)
            #expect(c == .zero, "\(String(describing: ratio)) → \(c)")
        }
    }

    @Test func handlesSitOnTheRect() {
        var rng = SplitMix64(state: 6)
        for _ in 0..<1000 {
            let r = randomRect(in: randomBounds(&rng), minSide: 0, &rng)
            for h in Handle.allCases {
                let p = handlePoint(h, of: r)
                #expect([r.minX, r.midX, r.maxX].contains(p.x) && [r.minY, r.midY, r.maxY].contains(p.y))
                #expect(p != pt(r.midX, r.midY) || r.width == 0 || r.height == 0)
            }
        }
    }
}
