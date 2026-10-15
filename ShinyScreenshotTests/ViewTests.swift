import AppKit
import SwiftUI
import Testing
@testable import ShinyScreenshot

/// Capture helpers and the AppKit-facing views, rendered offscreen. Nothing is shown on screen and no screen is captured.
struct ViewTests {
    // MARK: Capture

    @Test func pixelateKeepsTheSizeAtAnyScale() throws {
        for (w, h) in [(1, 1), (3, 2), (13, 7), (96, 96), (1440, 900)] {
            for scale: CGFloat in [1, 2, 3] {
                let out = try #require(Capture.pixelate(Fixture.coded(w, h), scale: scale), "\(w)×\(h) @\(scale)x")
                #expect(out.width == w && out.height == h, "\(w)×\(h) @\(scale)x → \(out.width)×\(out.height)")
            }
        }
    }

    @Test func pixelateReallyHidesDetail() throws {
        let input = Fixture.coded(240, 240)
        for scale: CGFloat in [1, 2] {
            let out = Pixels(try #require(Capture.pixelate(input, scale: scale)))
            var colours = Set<UInt32>()
            for y in 0..<out.height {
                for x in 0..<out.width {
                    let p = out[x, y]
                    colours.insert(UInt32(p.r) | UInt32(p.g) << 8 | UInt32(p.b) << 16)
                }
            }
            let block = Int(12 * scale), maxBlocks = (240 / block + 2) * (240 / block + 2)
            #expect(colours.count <= maxBlocks, "@\(scale)x: \(colours.count) colours, at most \(maxBlocks) blocks expected")
        }
    }

    /// Without noise, pixelated known text can be reversed by matching blocks (Depix). Each capture's noise differs,
    /// and on a flat grey it makes blocks both lighter and darker.
    @Test func pixelateAddsRandomPerBlockNoise() throws {
        let grey = Fixture.solid(240, 240, CGColor(gray: 0.5, alpha: 1))
        let a = Pixels(try #require(Capture.pixelate(grey, scale: 1)))
        let b = Pixels(try #require(Capture.pixelate(grey, scale: 1)))
        var lighter = 0, darker = 0, differ = 0
        for y in stride(from: 6, to: 240, by: 12) {
            for x in stride(from: 6, to: 240, by: 12) {
                let p = Int(a[x, y].r), mid = Int(Pixels(grey)[x, y].r)
                if p > mid + 2 { lighter += 1 } else if p < mid - 2 { darker += 1 }
                if !a[x, y].near(b[x, y], 2) { differ += 1 }
                #expect(a[x, y].r == a[x, y].g && a[x, y].g == a[x, y].b, "noise changes brightness only")
            }
        }
        #expect(lighter > 50 && darker > 50, "lighter \(lighter), darker \(darker) of 400 blocks")
        #expect(differ > 200, "\(differ) of 400 blocks differ between captures")
    }

    /// Reads window bounds only (CGWindowList metadata), never pixels.
    @Test func windowFramesAreLocalToTheirDisplay() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        for id in ids {
            let frame = CGDisplayBounds(id), local = CGRect(origin: .zero, size: frame.size)
            let windows = Capture.windowFrames(on: frame, excluding: getpid())
            print("WINDOWS display \(id) at \(frame): \(windows.count) selectable windows")
            for w in windows {
                #expect(local.contains(w), "\(w) outside \(local)")
                #expect(w.width > 40 && w.height > 40)
            }
        }
        #expect(Capture.windowFrames(on: CGRect(x: 100_000, y: -100_000, width: 1920, height: 1080), excluding: getpid()).isEmpty)
    }

    /// A display whose origin is not (0, 0) sees the same windows, shifted into its own coordinates.
    @Test func windowFramesShiftWithTheDisplayOrigin() {
        let main = CGDisplayBounds(CGMainDisplayID())
        let offset = CGRect(x: main.minX + 200, y: main.minY + 100, width: main.width - 300, height: main.height - 150)
        let local = CGRect(origin: .zero, size: offset.size)
        let expected = Capture.windowFrames(on: main, excluding: getpid())
            .map { $0.offsetBy(dx: -200, dy: -100).intersection(local) }
            .filter { $0.width > 40 && $0.height > 40 }
        #expect(Capture.windowFrames(on: offset, excluding: getpid()) == expected)
    }

    // MARK: Overlay

    @Test func overlayRendersEveryPhase() {
        for (w, h, scale) in [(800.0, 600.0, 1.0), (1440, 900, 2), (3008, 1692, 2)] as [(CGFloat, CGFloat, CGFloat)] {
            let s = Fixture.session(Fixture.gradient(Int(w * scale), Int(h * scale)), scale: scale,
                                    windows: [CGRect(x: 40, y: 40, width: w / 2, height: h / 2)])
            let selection = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.5, height: h * 0.5)
            let phases: [(String, () -> Void)] = [
                ("selecting", {}),
                ("hovering a window", { s.cursor = pt(60, 60) }),
                ("loupe at the top-left corner", { s.cursor = pt(0, 0) }),
                ("loupe at the bottom-right corner", { s.cursor = pt(w - 0.5, h - 0.5) }),
                ("editing with every tool", { s.selection = selection; s.phase = .editing; s.cursor = nil; s.annotateEverything(in: selection) }),
                ("typing a label", { s.tool = .text; s.tap(pt(selection.midX, selection.midY)); s.draft = "Typing" }),
                ("background", { s.commitText(); s.style.enabled = true }),
                ("transparent, portrait", { s.style.backdrop = .clear; s.style.ratio = .portrait }),
                ("wallpaper, 16:9, max padding", { s.style.backdrop = .boreal; s.style.ratio = .wide; s.style.padding = 160 }),
                ("full screen", { s.style.enabled = false; s.selectAll() }),
            ]
            for (name, setUp) in phases {
                setUp()
                let rep = timed("overlay snapshot \(Int(w))×\(Int(h)) @\(Int(scale))x, \(name)") {
                    snapshot(OverlayView(s: s) { _ in }, size: s.size)
                }
                #expect(rep.size == s.size, "\(name)")
            }
        }
    }

    @Test func toolbarFitsTheWidthItIsLaidOutFor() {
        let s = Fixture.session(Fixture.solid(1440, 900, CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)), scale: 1)
        s.selection = CGRect(x: 500, y: 200, width: 400, height: 300)
        s.phase = .editing
        let rep = snapshot(OverlayView(s: s) { _ in }, size: s.size)
        let k = CGFloat(rep.pixelsWide) / s.size.width
        let y = Int(s.toolbarCenter(around: s.selection).y * k)
        let background = rep.colorAt(x: 2, y: y)
        let xs = (0..<rep.pixelsWide).filter { rep.colorAt(x: $0, y: y) != background }
        let width = CGFloat((xs.last ?? 0) - (xs.first ?? 0) + 1) / k
        print("MEASURE toolbar width \(width) pt (toolbarCenter assumes 740)")
        #expect(width <= 2 * BackgroundTests.toolbarHalfWidth, "toolbar is \(width) pt")
        #expect(width > 600, "toolbar not found in the snapshot")
    }

    // MARK: Card and pin

    @Test func cardLaysOutForAnyImage() {
        let huge = NSImage(cgImage: Fixture.gradient(6016, 3384), size: CGSize(width: 3008, height: 1692))
        let images = [CGSize(width: 1, height: 1), CGSize(width: 8, height: 8), CGSize(width: 600, height: 400),
                      CGSize(width: 20, height: 3000), CGSize(width: 3000, height: 20)]
            .map { NSImage(cgImage: Fixture.gradient(Int($0.width), Int($0.height)), size: $0) } + [huge]
        for image in images {
            let card = CardView(title: "Copied to clipboard", image: image, drag: { NSItemProvider() }) { _ in }
            let host = NSHostingView(rootView: card)
            #expect(host.fittingSize == CGSize(width: 340, height: 300), "\(image.size) → \(host.fittingSize)")
            #expect(snapshot(card, size: host.fittingSize).size == host.fittingSize)
        }
    }

    @Test(.timeLimit(.minutes(1))) func cardDismissesItselfAfterSixSeconds() async throws {
        final class Log { var actions: [CardAction] = [] }
        let log = Log()
        let host = NSHostingView(rootView: CardView(title: "Saved", image: NSImage(size: CGSize(width: 10, height: 10)), drag: { NSItemProvider() }) {
            log.actions.append($0)
        })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host              // never ordered on screen
        let start = ContinuousClock.now
        try await Task.sleep(for: .seconds(5))
        #expect(log.actions.isEmpty, "dismissed early")
        while log.actions.isEmpty, ContinuousClock.now - start < .seconds(20) {
            try await Task.sleep(for: .milliseconds(50))
        }
        print("TIMING card auto-dismiss after \(ContinuousClock.now - start)")
        try await Task.sleep(for: .seconds(1))
        #expect(log.actions == [.dismiss])
        window.contentView = nil
    }

    @Test func pinTakesExactlyItsImageSize() {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 8, height: 8), CGSize(width: 15, height: 300),
                     CGSize(width: 720, height: 520), CGSize(width: 720, height: 1)] {
            let pin = PinView(image: NSImage(cgImage: Fixture.gradient(Int(size.width * 2), Int(size.height * 2)), size: size),
                              size: size, onClose: {}, onOpacity: { _ in })
            #expect(NSHostingView(rootView: pin).fittingSize == size, "\(size)")
            #expect(snapshot(pin, size: size).size == size)
        }
    }
}
