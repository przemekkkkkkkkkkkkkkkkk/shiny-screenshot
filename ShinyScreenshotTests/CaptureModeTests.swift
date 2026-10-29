import AppKit
import Testing
@testable import ShinyScreenshot

/// Scrolling stitch, single-window shots, window-only selecting, and the spotlight.
struct CaptureModeTests {
    // MARK: Stitching

    /// A tall "page" of coded rows; `frame(at:)` is what a 200-row viewport shows scrolled down by `y`.
    static let page = Fixture.coded(64, 1200)
    func frame(at y: Int, height: Int = 200) -> CGImage {
        Self.page.cropping(to: CGRect(x: 0, y: y, width: 64, height: height))!
    }

    @Test func offsetFindsHowFarItScrolled() {
        let a = Stitch.rows(frame(at: 0), ignoringRight: 0)
        for dy in [1, 37, 120, 192] {
            #expect(Stitch.offset(from: a, to: Stitch.rows(frame(at: dy), ignoringRight: 0)) == dy, "\(dy)")
        }
        #expect(Stitch.offset(from: a, to: a) == nil, "no scroll")
        #expect(Stitch.offset(from: a, to: Stitch.rows(frame(at: 400), ignoringRight: 0)) == nil, "no overlap")
        #expect(Stitch.offset(from: Stitch.rows(frame(at: 100), ignoringRight: 0), to: a) == nil, "scrolled up")
    }

    @Test func stickyHeaderAndBlankRowsDontWin() {
        // 30 rows that never move, then content scrolled by 50, and blank rows that match everywhere.
        let old = Array(0..<30) + Array(1000..<1170)
        let new = Array(0..<30) + Array(1050..<1170) + [Int](repeating: 7, count: 50)
        #expect(Stitch.offset(from: old, to: new) == 50)
    }

    @Test func stitchedFramesRebuildThePage() throws {
        var strips = [try #require(Stitch.copy(frame(at: 0)))]
        var last = Stitch.rows(frame(at: 0), ignoringRight: 0)
        for y in [40, 40, 150, 333, 500, 690, 880, 1000] {        // a repeat, small and large steps
            let f = frame(at: y)
            let rows = Stitch.rows(f, ignoringRight: 0)
            guard let dy = Stitch.offset(from: last, to: rows) else { continue }
            strips.append(try #require(Stitch.strip(f, from: f.height - dy)))
            last = rows
        }
        let image = try #require(Stitch.compose(strips))
        #expect(image.height == 1200 && image.width == 64)
        let got = Pixels(image), want = Pixels(Self.page)
        for y in stride(from: 0, to: 1200, by: 7) { #expect(got[5, y] == want[5, y], "row \(y)") }
    }

    @Test func scrollBarColumnIsIgnored() {
        let ctx = Fixture.context(64, 200)
        ctx.draw(frame(at: 30), in: CGRect(x: 0, y: 0, width: 64, height: 200))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 56, y: 0, width: 8, height: 200))   // a scroll bar over the right edge
        let a = Stitch.rows(frame(at: 0), ignoringRight: 10)
        #expect(Stitch.offset(from: a, to: Stitch.rows(ctx.makeImage()!, ignoringRight: 10)) == 30)
    }

    // MARK: Windows

    @Test func windowShotReplacesTheScreenOnlyWhileTheSelectionMatches() throws {
        let s = Fixture.session(Fixture.solid(400, 300, CGColor(red: 1, green: 0, blue: 0, alpha: 1)), scale: 1,
                                windows: [CGRect(x: 50, y: 50, width: 200, height: 100)])
        s.tap(pt(100, 100))
        #expect(s.selection == CGRect(x: 50, y: 50, width: 200, height: 100))
        // What Capture.window would bring back: the window alone, blue, with a see-through corner.
        let ctx = Fixture.context(200, 100)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 0, width: 190, height: 100))
        let window = ctx.makeImage()!
        s.windowShot = Capture.WindowShot(image: window, pixelated: window, frame: s.selection, selection: s.selection)

        let shot = Pixels(try #require(s.render()))
        #expect(shot[100, 50].b > 200 && shot[100, 50].r < 60, "\(shot[100, 50]) should be the window's blue")
        #expect(shot[2, 50].a == 0, "the window's transparent edge stays transparent")

        s.drag(pt(150, 100), pt(160, 100))                     // moved off the window: back to the screen
        let moved = Pixels(try #require(s.render()))[100, 50]
        #expect(moved.r > 200 && moved.b < 60, "\(moved) should be the screen's red")
    }

    @Test func windowModeIgnoresDragsButTakesClicks() {
        let s = Fixture.screen(1440, 900, windows: [CGRect(x: 100, y: 100, width: 600, height: 400)])
        s.windowsOnly = true
        s.drag(pt(800, 600), pt(1200, 800))
        #expect(s.phase == .selecting && s.selection.isEmpty)
        s.tap(pt(300, 300))
        #expect(s.phase == .editing && s.selection == CGRect(x: 100, y: 100, width: 600, height: 400))
    }

    // MARK: Spotlight

    @Test func spotlightDimsEverythingButItsBox() throws {
        let s = Fixture.session(Fixture.solid(400, 300, CGColor(gray: 1, alpha: 1)), scale: 1)
        s.drag(pt(0, 0), pt(400, 300))
        s.tool = .spotlight
        s.drag(pt(100, 100), pt(200, 200))
        s.tool = .rect
        s.drag(pt(300, 20), pt(380, 80))                       // marks outside the spotlight stay bright
        let p = Pixels(try #require(s.render()))
        #expect(p[150, 150].near(RGBA(r: 255, g: 255, b: 255, a: 255)))
        #expect(p[20, 250].r < 160 && p[20, 250].a == 255)
        #expect(p[300, 50].near(RGBA(r: 255, g: 59, b: 48, a: 255), 30), "\(p[300, 50])")
    }

    // MARK: Memory and file size

    @Test func blurCopyIsMadeLazilyAndRemadeTheSame() throws {
        let s = Fixture.session(Fixture.coded(400, 300), scale: 1)
        #expect(s.pixelated == nil, "freezing doesn't pixelate")
        s.drag(pt(0, 0), pt(400, 300))
        s.tool = .blur
        s.drag(pt(50, 50), pt(250, 200))
        let first = Pixels(try #require(s.render()))
        #expect(s.pixelated != nil, "export makes it on the spot")
        s.releasePixelated()
        #expect(s.pixelated == nil)
        let again = Pixels(try #require(s.render()))
        #expect(first[100, 100] == again[100, 100], "same noise after remaking, so exports can't be averaged")
    }

    @Test func olderRecentShotsDropTheirSession() throws {
        let s = Fixture.session(Fixture.gradient(200, 100), scale: 1)
        s.selectAll()
        let shot = try #require(Shot(s))
        #expect(shot.editable && shot.session === s)
        let old = shot.withoutSession
        #expect(!old.editable && old.session == nil && old.cgImage === shot.cgImage && old.size == shot.size)
    }

    @Test func opaqueShotsSaveWithoutAlpha() throws {
        let s = Fixture.session(Fixture.coded(600, 400), scale: 2)
        s.selectAll()
        let opaque = try #require(Shot(s))
        #expect(opaque.opaque)
        s.style.enabled = true
        s.style.backdrop = .clear
        #expect(!(try #require(Shot(s))).opaque, "a transparent background keeps its alpha")

        let rgb = try #require(Shot.png(opaque.cgImage, size: opaque.size, opaque: true))
        let rgba = try #require(Shot.png(opaque.cgImage, size: opaque.size))
        let rep = try #require(NSBitmapImageRep(data: rgb))
        #expect(!rep.hasAlpha && rep.size == opaque.size)
        #expect(rgb.count < rgba.count, "\(rgb.count) vs \(rgba.count) bytes")
        let a = Pixels(try #require(rep.cgImage)), b = Pixels(opaque.cgImage)
        for (x, y) in [(0, 0), (123, 45), (599, 399)] { #expect(a[x, y] == b[x, y], "lossless at \(x), \(y)") }
    }
}
