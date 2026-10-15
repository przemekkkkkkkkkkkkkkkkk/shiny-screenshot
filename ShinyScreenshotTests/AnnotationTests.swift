import SwiftUI
import Testing
@testable import ShinyScreenshot

/// Every annotation tool, driven through Session's gesture entry points.
struct AnnotationTests {
    static let selection = CGRect(x: 100, y: 100, width: 600, height: 400)
    static let dragTools: [Tool] = [.arrow, .rect, .highlight, .blur, .pen]

    let s: Session

    init() {
        s = Fixture.screen(1440, 900)
        s.drag(pt(100, 100), pt(700, 500))
    }

    var steps: [Int] { s.annotations.filter { $0.tool == .step }.map(\.number) }

    // MARK: Drawn tools

    @Test func dragToolsDrawWhereTheMouseWent() {
        for tool in Self.dragTools {
            let s = Fixture.screen(1440, 900)
            s.drag(pt(100, 100), pt(700, 500))
            s.tool = tool
            s.color = palette[4]
            s.drag(pt(200, 200), pt(400, 300))
            #expect(s.annotations.count == 1, "\(tool)")
            guard let a = s.annotations.first else { continue }
            #expect(a.tool == tool && a.color == palette[4])
            #expect(a.points.first == pt(200, 200) && a.points.last == pt(400, 300), "\(tool)")
            #expect(tool == .pen ? a.points.count > 2 : a.points.count == 2, "\(tool)")
            #expect(s.selection == Self.selection, "drawing must not move the selection")
        }
    }

    @Test func tinyDragsDrawNothing() {
        for tool in Self.dragTools {
            s.tool = tool
            s.drag(pt(200, 200), pt(202, 201))
            #expect(s.annotations.isEmpty, "\(tool)")
        }
        for tool in [Tool.arrow, .rect, .highlight, .blur] {   // out and back: the final shape is a dot
            s.tool = tool
            s.drag(through: [pt(300, 300), pt(450, 380), pt(301, 301)])
            #expect(s.annotations.isEmpty, "\(tool)")
        }
    }

    @Test func penLoopThatEndsWhereItStartedIsKept() {
        s.tool = .pen
        s.drag(through: (0...64).map { i in
            let t = Double(i) / 64 * 2 * .pi
            return pt(400 + 80 * cos(t), 300 + 80 * sin(t))
        })
        #expect(s.annotations.count == 1)
    }

    @Test func penHandlesTenThousandPoints() throws {
        s.tool = .pen
        let points = (0..<10_000).map { i in pt(110 + CGFloat(i % 580), 110 + CGFloat(i / 580 * 20) + (i.isMultiple(of: 2) ? 0 : 5)) }
        timed("pen drag with 10 000 points") { s.drag(through: points) }
        #expect(s.annotations.count == 1)
        #expect(s.annotations.first?.points.count == points.count + 2)
        let image = try #require(timed("render 600×400 with a 10 000-point pen stroke") { s.render() })
        #expect(image.width == 600 && image.height == 400)
    }

    @Test func undoDuringADrawDoesNotCrash() {
        s.tool = .arrow
        s.dragChanged(from: pt(200, 200), to: pt(200, 200))
        s.dragChanged(from: pt(200, 200), to: pt(300, 300))
        s.undo()
        s.dragChanged(from: pt(200, 200), to: pt(350, 300))
        s.dragEnded(from: pt(200, 200), to: pt(350, 300))
        #expect(s.annotations.isEmpty)
    }

    @Test func aGestureThatNeverEndsDoesNotHijackTheNextOne() {
        s.tool = .arrow
        // Mid-drag, Return copies and closes the overlay, so onEnded never arrives.
        s.dragChanged(from: pt(200, 200), to: pt(200, 200))
        s.dragChanged(from: pt(200, 200), to: pt(300, 250))
        // The card's Edit button reopens the same session and the user draws again elsewhere.
        s.drag(pt(400, 400), pt(500, 450))
        #expect(s.annotations.count == 2)
        #expect(s.annotations.first?.points == [pt(200, 200), pt(300, 250)])
    }

    // MARK: Steps

    @Test func stepsNumberInOrderAndUndoFreesTheLastNumber() {
        s.tool = .step
        for x: CGFloat in [200, 250, 300] { s.tap(pt(x, 200)) }
        #expect(steps == [1, 2, 3])
        s.undo()
        #expect(steps == [1, 2])
        s.tap(pt(350, 200))
        #expect(steps == [1, 2, 3])
        s.tool = .arrow
        s.drag(pt(200, 300), pt(300, 350))
        s.tool = .step
        s.tap(pt(400, 200))
        #expect(steps == [1, 2, 3, 4])
        s.undo()
        s.undo()                               // the step, then the arrow
        #expect(steps == [1, 2, 3] && s.annotations.count == 3)
        for _ in 0..<10 { s.undo() }
        #expect(s.annotations.isEmpty)
        s.tap(pt(200, 200))
        #expect(steps == [1])
    }

    @Test func stepNumbersRestartForANewSelection() {
        s.tool = .step
        s.tap(pt(200, 200))
        s.tap(pt(300, 200))
        s.drag(pt(900, 600), pt(1300, 850))    // a new selection away from the old steps
        s.tap(pt(1000, 700))
        #expect(s.annotations.last?.number == 1)
    }

    // MARK: Text

    @Test func textIsPlacedOnClickAndCommittedTrimmed() throws {
        s.tool = .text
        s.tap(pt(300, 300))
        let id = try #require(s.editingText)
        #expect(s.annotations.map(\.id) == [id])
        #expect(s.draft == "")
        s.draft = "  Hello  \n"
        s.commitText()
        #expect(s.editingText == nil)
        #expect(s.annotations.map(\.text) == ["Hello"])
    }

    @Test func emptyTextIsDiscarded() {
        s.tool = .text
        s.tap(pt(300, 300))
        s.draft = "  \n "
        s.commitText()
        #expect(s.annotations.isEmpty && s.editingText == nil)
        s.commitText()                         // nothing being edited: a no-op
        #expect(s.annotations.isEmpty)
    }

    @Test func clickingAgainCommitsThePreviousLabel() {
        s.tool = .text
        s.tap(pt(300, 300))
        s.draft = "One"
        s.tap(pt(300, 400))
        #expect(s.annotations.map(\.text) == ["One", ""])
        #expect(s.editingText == s.annotations.last?.id)
        #expect(s.draft == "")
    }

    @Test func drawingWithAnotherToolCommitsTheLabel() {
        s.tool = .text
        s.tap(pt(300, 300))
        s.draft = "One"
        s.tool = .arrow                        // picked from the toolbar while typing
        s.drag(pt(200, 200), pt(300, 250))
        #expect(s.editingText == nil)
        #expect(s.annotations.map(\.tool) == [.text, .arrow])
        #expect(s.annotations.first?.text == "One")
    }

    @Test func draggingWithTheTextToolPlacesNothing() {
        s.tool = .text
        s.drag(pt(300, 300), pt(400, 400))
        #expect(s.annotations.isEmpty && s.editingText == nil)
    }

    @Test func undoWhileTypingLeavesNoDanglingEditor() {
        s.tool = .text
        s.tap(pt(300, 300))
        s.draft = "abc"
        s.undo()                               // the toolbar's Undo button; ⌘Z goes to the field instead
        #expect(s.editingText.map { id in s.annotations.contains { $0.id == id } } ?? true)
    }

    // MARK: Placement

    @Test func clicksOutsideTheSelectionPlaceNothing() {
        for tool in [Tool.step, .text] {
            s.tool = tool
            s.tap(pt(900, 700))
            #expect(s.annotations.isEmpty && s.editingText == nil, "\(tool)")
            #expect(s.selection == Self.selection)
        }
    }

    @Test func annotationsMayRunOffTheSelectionAndAreClipped() throws {
        s.tool = .arrow
        s.drag(pt(600, 400), pt(2000, 1500))
        #expect(s.annotations.first?.points.last == pt(2000, 1500))
        let image = try #require(s.render())
        #expect(image.width == 600 && image.height == 400)
    }

    @Test func backgroundModeLocksTheSelectionAndAnnotations() {
        s.style.enabled = true
        for tool in [nil] + Tool.allCases {
            s.tool = tool
            s.drag(pt(200, 200), pt(400, 300))                 // inside: no move, no drawing
            s.tap(pt(300, 300))                                // no step, no label
            s.drag(pt(700, 500), pt(800, 600))                 // a handle: no resize
            s.drag(pt(900, 700), pt(1000, 800))                // outside: no new selection
            #expect(s.annotations.isEmpty && s.editingText == nil, "\(String(describing: tool))")
            #expect(s.selection == Self.selection, "\(String(describing: tool))")
        }
    }

    @Test func yellowLabelsUseDarkText() {
        // draw(_:) picks black text when the colour equals .mark; palette[2] is the same hex.
        #expect(palette[2] == Color.mark)
    }
}
