import CoreGraphics
import Testing
@testable import ShinyScreenshot

/// Session's selection state machine: drag to create, click a window, move, resize, and the edge cases between.
struct SelectionTests {
    static let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let windows = [CGRect(x: 100, y: 100, width: 600, height: 400),   // front
                          CGRect(x: 300, y: 200, width: 500, height: 500),   // behind the first
                          CGRect(x: 1300, y: 800, width: 400, height: 300)]  // hangs off the bottom-right corner
    static let typical = CGRect(x: 200, y: 150, width: 700, height: 450)

    let s = Fixture.screen(1440, 900, windows: windows)

    /// A session in the editing phase with `typical` selected.
    func editing() -> Session {
        let s = Fixture.screen(1440, 900)
        s.drag(pt(200, 150), pt(900, 600))
        return s
    }

    // MARK: Creating

    @Test func dragCreatesSelectionInAnyDirection() {
        for (a, b) in [(pt(200, 150), pt(900, 600)), (pt(900, 600), pt(200, 150)),
                       (pt(900, 150), pt(200, 600)), (pt(200, 600), pt(900, 150))] {
            let s = Fixture.screen(1440, 900)
            s.drag(a, b)
            #expect(s.selection == Self.typical, "\(a) → \(b)")
            #expect(s.phase == .editing)
        }
    }

    @Test func dragPastTheScreenEdgeIsClipped() {
        s.drag(pt(1000, 500), pt(2500, 1700))
        #expect(s.selection == CGRect(x: 1000, y: 500, width: 440, height: 400))
        let t = Fixture.screen(1440, 900)
        t.drag(pt(100, 80), pt(-400, -300))
        #expect(t.selection == CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    @Test func jitterUnderThreePointsIsAClickNotADrag() {
        s.drag(pt(1000, 700), pt(1002, 701))   // no window there
        #expect(s.phase == .selecting)
        #expect(s.selection == .zero)
    }

    @Test func clickSelectsTheFrontmostWindowUnderThePoint() {
        s.tap(pt(350, 250))                    // inside windows 0 and 1
        #expect(s.selection == Self.windows[0])
        #expect(s.phase == .editing)

        let t = Fixture.screen(1440, 900, windows: Self.windows)
        t.tap(pt(750, 650))                    // only window 1
        #expect(t.selection == Self.windows[1])

        let u = Fixture.screen(1440, 900, windows: Self.windows)
        u.tap(pt(1350, 850))                   // clipped to the screen
        #expect(u.selection == CGRect(x: 1300, y: 800, width: 140, height: 100))
    }

    @Test func clickOnBareDesktopKeepsSelecting() {
        s.tap(pt(1000, 50))
        #expect(s.phase == .selecting)
        #expect(s.selection == .zero)
    }

    @Test func hoveredWindowFollowsTheCursorUntilSomethingIsSelected() {
        s.cursor = pt(350, 250)
        #expect(s.hoveredWindow == Self.windows[0])
        s.cursor = pt(1000, 50)
        #expect(s.hoveredWindow == nil)
        s.cursor = pt(750, 650)
        #expect(s.hoveredWindow == Self.windows[1])
        s.drag(pt(1000, 50), pt(1200, 300))
        #expect(s.hoveredWindow == nil)
    }

    @Test func dragOutsideTheSelectionStartsANewOne() {
        let s = editing()
        s.drag(pt(1000, 100), pt(1200, 300))
        #expect(s.selection == CGRect(x: 1000, y: 100, width: 200, height: 200))
        #expect(s.phase == .editing)
    }

    // MARK: Drags that end up too small

    @Test func thinDragLeavesNoStaleSelection() {
        s.drag(pt(1000, 300), pt(1300, 302))   // 300 × 2: too thin to edit
        #expect(s.phase == .selecting)
        s.cursor = pt(350, 250)
        #expect(s.selection.isEmpty)                     // the 300×2 sliver stays; Return copies it
        #expect(s.hoveredWindow == Self.windows[0])      // and window hover is gone until the next drag
    }

    @Test func dragThatReturnsToItsStartLeavesNoStaleSelection() {
        s.drag(through: [pt(1000, 300), pt(1100, 400), pt(1050, 350), pt(1003, 302), pt(1001, 300)])
        #expect(s.phase == .selecting)
        #expect(s.selection.isEmpty)
    }

    @Test func abandonedDragKeepsTheExistingSelection() {
        let s = editing()
        s.drag(through: [pt(1100, 300), pt(1300, 500), pt(1150, 350), pt(1103, 302), pt(1101, 300)])
        #expect(s.phase == .editing)
        #expect(s.selection == Self.typical)
    

        let t = editing()
        t.drag(pt(1100, 300), pt(1300, 302))
        #expect(t.selection == Self.typical)
        #expect(t.phase == .editing)                     // …and dropped back to selecting
    }

    // MARK: Moving and resizing

    @Test func moveFollowsTheDragAndStopsAtEveryEdge() {
        let cases: [(CGSize, CGRect)] = [
            (CGSize(width: 40, height: -30), CGRect(x: 240, y: 120, width: 700, height: 450)),
            (CGSize(width: -5000, height: 0), CGRect(x: 0, y: 150, width: 700, height: 450)),
            (CGSize(width: 5000, height: 0), CGRect(x: 740, y: 150, width: 700, height: 450)),
            (CGSize(width: 0, height: -5000), CGRect(x: 200, y: 0, width: 700, height: 450)),
            (CGSize(width: 0, height: 5000), CGRect(x: 200, y: 450, width: 700, height: 450)),
            (CGSize(width: 5000, height: 5000), CGRect(x: 740, y: 450, width: 700, height: 450)),
        ]
        for (d, expected) in cases {
            let s = editing()
            s.drag(pt(550, 375), pt(550 + d.width, 375 + d.height))
            #expect(s.selection == expected, "\(d)")
        }
    }

    @Test func everyHandleResizesOnlyItsOwnEdges() {
        let expected: [Handle: CGRect] = [
            .nw: CGRect(x: 230, y: 170, width: 670, height: 430), .n: CGRect(x: 200, y: 170, width: 700, height: 430),
            .ne: CGRect(x: 200, y: 170, width: 730, height: 430), .e: CGRect(x: 200, y: 150, width: 730, height: 450),
            .se: CGRect(x: 200, y: 150, width: 730, height: 470), .s: CGRect(x: 200, y: 150, width: 700, height: 470),
            .sw: CGRect(x: 230, y: 150, width: 670, height: 470), .w: CGRect(x: 230, y: 150, width: 670, height: 450),
        ]
        for h in Handle.allCases {
            let s = editing()
            let p = handlePoint(h, of: s.selection)
            s.drag(p, pt(p.x + 30, p.y + 20))
            #expect(s.selection == expected[h], "\(h)")
        }
    }

    @Test func resizeIsClampedAtEveryScreenEdgeAndMinimumSize() {
        let far: CGFloat = 5000
        for h in Handle.allCases {
            for d in [CGSize(width: -far, height: -far), CGSize(width: far, height: far),
                      CGSize(width: far, height: -far), CGSize(width: -far, height: far)] {
                let s = editing()
                let p = handlePoint(h, of: s.selection)
                s.drag(p, pt(p.x + d.width, p.y + d.height))
                #expect(Self.bounds.contains(s.selection), "\(h) \(d): \(s.selection)")
                #expect(s.selection.width >= 8 && s.selection.height >= 8, "\(h) \(d): \(s.selection)")
            }
        }
    }

    @Test func smallSelectionCanStillBeMovedAndDrawnIn() {
        let s = Fixture.screen(1440, 900)
        s.drag(pt(500, 500), pt(514, 514))
        #expect(s.phase == .editing)
        s.drag(pt(507, 507), pt(607, 607))     // grab the middle and move it
        #expect(s.selection == CGRect(x: 600, y: 600, width: 14, height: 14))
    

        let t = Fixture.screen(1440, 900)
        t.drag(pt(500, 500), pt(519, 519))
        t.tool = .arrow
        t.drag(pt(509.5, 509.5), pt(516, 516))
        #expect(t.annotations.count == 1)
    }

    @Test func selectionsUnderTheMinimumAreNotKept() {
        let s = Fixture.screen(1440, 900)
        s.drag(pt(0, 0), pt(5, 5))
        #expect(s.phase == .selecting && s.selection.isEmpty)
        s.drag(pt(0, 0), pt(8, 8))
        #expect(s.phase == .editing && s.selection == CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    @Test func smallestSelectionInACornerStaysOnScreenWhenTouched() throws {
        let s = Fixture.screen(1440, 900)
        s.drag(pt(0, 0), pt(8, 8))
        s.tap(pt(1, 1))
        s.drag(pt(1, 1), pt(-50, -50))
        #expect(Self.bounds.contains(s.selection) && s.selection.width >= 8 && s.selection.height >= 8)
        let image = try #require(s.render())
        #expect(Pixels(image)[0, 0].a == 255)
    }

    @Test func fullScreenSelection() {
        s.selectAll()
        #expect(s.selection == Self.bounds)
        #expect(s.phase == .editing)
        s.drag(pt(720, 450), pt(1000, 700))    // moving is clamped, and every point is inside, so no new selection
        #expect(s.selection == Self.bounds)
        s.drag(pt(0, 0), pt(100, 50))
        #expect(s.selection == CGRect(x: 100, y: 50, width: 1340, height: 850))
        s.drag(pt(1440, 900), pt(1400, 880))
        #expect(s.selection == CGRect(x: 100, y: 50, width: 1300, height: 830))
    }

    // MARK: Fuzz

    /// Thousands of random gestures, taps, tool switches, undos and text edits on several screens.
    /// Hard invariants must always hold; the soft ones are known bugs and are counted.
    @Test func rapidRandomGesturesKeepTheSessionSane() {
        var rng = SplitMix64(state: 0x5348_4E59)
        var stale = 0, tinyEditing = 0, offScreen = 0, dangling = 0
        for (w, h, scale) in [(1440.0, 900.0, 1.0), (1512, 982, 2), (3008, 1692, 2), (800, 600, 1)] as [(CGFloat, CGFloat, CGFloat)] {
            let bounds = CGRect(x: 0, y: 0, width: w, height: h)
            let windows = (0..<6).map { _ in
                CGRect(x: .random(in: 0...w - 100, using: &rng), y: .random(in: 0...h - 100, using: &rng),
                       width: .random(in: 41...w / 2, using: &rng), height: .random(in: 41...h / 2, using: &rng)).intersection(bounds)
            }
            let s = Fixture.screen(w, h, scale: scale, windows: windows)
            func inside() -> CGPoint { pt(.random(in: 0..<w, using: &rng), .random(in: 0..<h, using: &rng)) }
            func anywhere() -> CGPoint { pt(.random(in: -150...w + 150, using: &rng), .random(in: -150...h + 150, using: &rng)) }
            func near(_ p: CGPoint, _ r: CGFloat) -> CGPoint { pt(p.x + .random(in: -r...r, using: &rng), p.y + .random(in: -r...r, using: &rng)) }

            for step in 0..<1500 {
                switch Int.random(in: 0..<100, using: &rng) {
                case 0..<40:
                    let a = inside()
                    s.drag(through: [a] + (0..<Int.random(in: 1...8, using: &rng)).map { _ in Bool.random(using: &rng) ? anywhere() : near(a, 6) })
                case 40..<55: s.tap(inside())
                case 55..<62: let a = inside(); s.drag(a, near(a, 2))
                case 62..<70: let a = handlePoint(Handle.allCases.randomElement(using: &rng)!, of: s.selection); s.drag(near(a, 9), anywhere())
                case 70..<78: s.tool = ([nil] + Tool.allCases).randomElement(using: &rng)!
                case 78..<84: s.undo()
                case 84..<90:
                    s.draft = ["", "  ", "hi", "a longer label"].randomElement(using: &rng)!
                    if Bool.random(using: &rng) { s.commitText() }
                case 90..<93: s.style.enabled.toggle()
                case 93..<95: s.selectAll()
                default: s.style.enabled = false
                }

                let sel = s.selection
                #expect(!sel.isNull && sel.minX.isFinite && sel.minY.isFinite && sel.width >= 0 && sel.height >= 0,
                        "\(w)×\(h) step \(step): \(sel)")
                for a in s.annotations {
                    #expect(!a.points.isEmpty && a.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    if a.tool == .step { #expect(a.number >= 1) }
                }
                if s.phase == .selecting && !sel.isEmpty { stale += 1 }
                if s.phase == .editing && (sel.width <= 4 || sel.height <= 4) { tinyEditing += 1 }
                if !sel.isEmpty && !bounds.insetBy(dx: -1e-9, dy: -1e-9).contains(sel) { offScreen += 1 }
                if let id = s.editingText, !s.annotations.contains(where: { $0.id == id }) { dangling += 1 }
            }
        }
        print("FUZZ session: stale \(stale), tinyEditing \(tinyEditing), offScreen \(offScreen), dangling \(dangling) (of 6000 steps)")
        #expect(stale == 0)
        #expect(tinyEditing == 0)
        #expect(offScreen == 0)
        #expect(dangling == 0)
    }
}
