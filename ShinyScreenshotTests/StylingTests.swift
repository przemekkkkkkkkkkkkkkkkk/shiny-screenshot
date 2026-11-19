import AVFoundation
import SwiftUI
import Testing
@testable import ShinyScreenshot

/// The expanded background panel: old styles still load, frames and rings grow the layout, sizes, privacy and colours.
struct StylingTests {
    func styled(_ w: CGFloat = 800, _ h: CGFloat = 600, selection: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)) -> Session {
        let s = Fixture.session(Fixture.coded(Int(w), Int(h)), scale: 1)
        s.selection = selection
        s.phase = .editing
        s.style.enabled = true
        return s
    }

    @Test func stylesSavedBeforeTheNewFieldsStillLoad() throws {
        let old = #"{"enabled":true,"backdrop":"dusk","padding":64,"radius":12,"shadow":0.5,"ratio":"16:9","eyebrow":"","title":"Hi","subtitle":"","heading":"Headline","font":"Sans","weight":"Bold","align":"Centre","below":false,"textScale":1,"textShadow":false}"#
        let s = try JSONDecoder().decode(Style.self, from: Data(old.utf8))
        #expect(s.backdrop == .dusk && s.padding == 64 && s.title == "Hi" && s.ratio == .wide)
        #expect(s.frame == .none && s.shadowLook == .soft && s.fill == .backdrop && s.zoom == 1)
        let round = try JSONDecoder().decode(Style.self, from: JSONEncoder().encode(s))
        #expect(round.backdrop == .dusk && round.frame == .none)
    }

    @Test func frameAndRingGrowTheBoxAndKeepTheShotOnThePixelGrid() {
        let s = styled()
        let plain = s.canvas
        s.style.frame = .safari
        s.style.inset = 12
        let c = s.style.frame.chrome
        #expect(s.boxSize == CGSize(width: 400 + 24, height: 300 + c.top + 24))
        #expect(s.canvas.height == plain.height + c.top + 24 && s.canvas.width == plain.width + 24)
        let o = s.shotOrigin, box = s.boxFrame
        #expect(o.x == o.x.rounded() && o.y == o.y.rounded())
        #expect(box.minX == o.x - 12 && box.minY == o.y - 12 - c.top)
    }

    @Test func platformAndCustomSizesSetTheAspect() {
        let s = styled()
        s.style.platform = .instagram
        #expect(abs(s.canvas.width / s.canvas.height - 1080.0 / 1350.0) < 0.01)
        s.style.customSize = CGSize(width: 3000, height: 1000)
        #expect(abs(s.canvas.width / s.canvas.height - 3) < 0.01)
    }

    @Test func placementMovesTheShotInsideTheSlack() {
        let s = styled()
        s.style.ratio = .wide
        s.style.placement = .left
        let left = s.shotOrigin.x
        s.style.placement = .right
        let right = s.shotOrigin.x
        #expect(left == s.style.padding && right > left)
        s.style.autoBalance = true
        #expect(abs(s.shotOrigin.x - (s.canvas.width - 400) / 2) <= 1)
    }

    @Test func bleedRunsTheShotOffTheBottom() {
        let s = styled()
        s.style.bleed = true
        s.style.placement = .bottom
        #expect(s.shotOrigin.y + 300 > s.canvas.height)
    }

    @Test func everyOptionRendersAtTheCanvasSize() throws {
        let s = styled()
        let variations: [(inout Style) -> Void] = [
            { $0.frame = .mac }, { $0.frame = .macbook; $0.shotLook = .liquid }, { $0.layout = .duo }, { $0.layout = .stack },
            { $0.tilt = .iso }, { $0.pattern = .waves; $0.noise = 0.4 }, { $0.light = .blinds; $0.vfx = .vhs }, { $0.shapes = .orbs },
            { $0.watermark = true }, { $0.fill = .custom; $0.gradient.kind = .conic }, { $0.canvasRadius = 24 }, { $0.shadowLook = .hard },
        ]
        for change in variations {
            var st = s.style
            change(&st)
            s.style = st
            let image = try #require(s.render())
            #expect(image.width == Int(s.canvas.width) && image.height == Int(s.canvas.height))
            s.style = Style()
            s.style.enabled = true
        }
    }

    @Test func exportSizesScaleTheCanvas() {
        let s = styled()
        s.style.size = .uhd
        #expect(abs(s.canvas.width * s.exportScale - 3840) < 0.5)
        s.style.size = .x2
        #expect(s.exportScale == 2)
        s.style.canvasRadius = 10
        #expect(!s.isOpaque)
    }

    @Test func saveWritesTheChosenFormatAtTheChosenSize() throws {
        let s = styled()
        s.style.format = .jpeg
        s.style.size = .x2
        let shot = try #require(Shot(s))
        #expect(shot.size == s.canvas, "pastes at the canvas size")
        #expect(CGFloat(shot.cgImage.width) == s.canvas.width * 2)
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(shot.save(to: dir))
        #expect(url.pathExtension == "jpg")
        #expect(NSImage(contentsOf: url) != nil)
    }

    @Test func sensitiveTextIsFound() {
        func found(_ t: String) -> [String] { sensitiveRanges(in: t).map { String(t[$0]) } }
        #expect(found("mail jane@acme.co now") == ["jane@acme.co"])
        #expect(found("key sk_live_51HqAbCdEf9fA2") == ["sk_live_51HqAbCdEf9fA2"])
        #expect(found("card 4242 4242 4242 4242") == ["4242 4242 4242 4242"])
        #expect(found("server 192.168.1.20 up") == ["192.168.1.20"])
        #expect(found("AKIAIOSFODNN7EXAMPLE") == ["AKIAIOSFODNN7EXAMPLE"])
        #expect(found("Revenue grew 12% this week").isEmpty)
    }

    @Test func dominantColorsFindTheShotsColours() {
        let ctx = Fixture.context(64, 64)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        let c = dominantColors(ctx.makeImage()!, count: 2)
        #expect(Set(c) == [0xFF0000, 0x0000FF])
        #expect(magicGradients(c).count == 8)
    }

    @Test func videoSizesAreEvenAndCapped() {
        let p = Video.pixels(CGSize(width: 1001, height: 333), scale: 2)
        #expect(p.w % 2 == 0 && p.h % 2 == 0 && p.w <= 2002)
        let big = Video.pixels(CGSize(width: 6000, height: 3000), scale: 2)
        #expect(big.w <= 3840)
        for m in Motion.allCases {
            let start = Video.pose(m, t: 0, canvas: CGSize(width: 800, height: 600)), end = Video.pose(m, t: 1, canvas: CGSize(width: 800, height: 600))
            #expect(start != end || m == .float || m == .parallax, "\(m) moves")
        }
    }

    @Test func motionAndStyledVideosWriteMP4s() async throws {
        let s = styled()
        s.style.frame = .mac
        s.style.seconds = 0.5
        s.style.motion = .parallax
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let still = dir.appending(path: "still.mp4")
        try await Video.motion(s, to: still) { _ in }
        let track = try #require(try await AVURLAsset(url: still).loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width) % 2 == 0 && size.width > 0)
        #expect(try await AVURLAsset(url: still).load(.duration).seconds > 0.4)

        // The motion file stands in for a recording of the selection.
        let rec = Fixture.session(Fixture.coded(800, 600), scale: 1)
        rec.selection = CGRect(x: 0, y: 0, width: 400, height: 300)
        rec.phase = .editing
        rec.video = still
        rec.style.enabled = true
        rec.style.backdrop = .dusk
        rec.style.tilt = .iso
        let out = dir.appending(path: "styled.mp4")
        try await Video.styled(rec, to: out)
        let t = try #require(try await AVURLAsset(url: out).loadTracks(withMediaType: .video).first)
        let n = try await t.load(.naturalSize)
        #expect(abs(n.width - rec.canvas.width) <= 2 && abs(n.height - rec.canvas.height) <= 2, "\(n) vs \(rec.canvas)")
        #expect(rec.style.tilt == .iso, "style restored after export")
    }

    @Test func autoBalanceEvensThePlainMarginAroundTheContent() {
        // White screen with a red block: 20 px from the left and top of the selection, 80 px from the right and bottom.
        let ctx = Fixture.context(400, 300)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        // CGContext's origin is bottom-left: the block spans y 120…200 from the top.
        ctx.fill(CGRect(x: 120, y: 100, width: 100, height: 80))
        let s = Fixture.session(ctx.makeImage()!, scale: 1)
        s.selection = CGRect(x: 100, y: 100, width: 200, height: 180)
        s.phase = .editing
        s.style.enabled = true
        let m = plainMargins(s.image.cropping(to: s.selection)!)
        #expect(m?.left == 20 && m?.top == 20 && m?.right == 80 && m?.bottom == 80, "\(String(describing: m))")
        s.style.autoBalance = true
        #expect(s.shotArea == CGRect(x: 100, y: 100, width: 140, height: 120), "\(s.shotArea)")
        let image = s.render()!
        #expect(image.width == Int(s.canvas.width))
        s.style.autoBalance = false
        #expect(s.shotArea == s.selection)
        // Nothing plain at the edges: nothing to trim.
        let busy = styled()
        busy.style.autoBalance = true
        #expect(busy.shotArea == busy.selection)
    }
}
