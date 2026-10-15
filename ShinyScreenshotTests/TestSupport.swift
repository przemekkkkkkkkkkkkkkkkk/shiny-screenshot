import AppKit
import SwiftUI
@testable import ShinyScreenshot

/// Synthetic screens for building Sessions in-process. Nothing here touches the real display.
enum Fixture {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Every pixel's colour encodes its position (r = x, g = y, b = their high bits),
    /// so a test can tell exactly where an exported pixel came from.
    static func coded(_ w: Int, _ h: Int) -> CGImage {
        let ctx = context(w, h)
        let p = ctx.data!.bindMemory(to: UInt32.self, capacity: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let high = UInt32(((x >> 8) << 4 | (y >> 8)) & 0xFF)
                p[y * w + x] = UInt32(x & 0xFF) | UInt32(y & 0xFF) << 8 | high << 16 | 0xFF00_0000
            }
        }
        return ctx.makeImage()!
    }

    /// One-pixel black and white checkerboard: any resampling turns it grey.
    static func checker(_ w: Int, _ h: Int) -> CGImage {
        let ctx = context(w, h)
        let p = ctx.data!.bindMemory(to: UInt32.self, capacity: w * h)
        for y in 0..<h {
            for x in 0..<w { p[y * w + x] = (x + y).isMultiple(of: 2) ? 0xFFFF_FFFF : 0xFF00_0000 }
        }
        return ctx.makeImage()!
    }

    /// Cheap at any size, for the huge screens.
    static func gradient(_ w: Int, _ h: Int) -> CGImage {
        let ctx = context(w, h)
        let colors = [CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1), CGColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1)]
        let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
        return ctx.makeImage()!
    }

    static func solid(_ w: Int, _ h: Int, _ color: CGColor) -> CGImage {
        let ctx = context(w, h)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// A session over `image`, built the way Capture.freeze builds one (pixelated copy included).
    static func session(_ image: CGImage, scale: CGFloat, windows: [CGRect] = []) -> Session {
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let frozen = Capture.Frozen(image: image, pixelated: Capture.pixelate(image, scale: scale) ?? image,
                                    scale: scale, size: size, windows: windows)
        return Session(frozen, displayID: 0)
    }

    /// For state-machine tests that never look at pixels: a screen of any point size backed by a 1-pixel image.
    static func screen(_ w: CGFloat, _ h: CGFloat, scale: CGFloat = 1, windows: [CGRect] = []) -> Session {
        let image = solid(1, 1, CGColor(gray: 0.5, alpha: 1))
        return Session(Capture.Frozen(image: image, pixelated: image, scale: scale, size: CGSize(width: w, height: h), windows: windows),
                       displayID: 0)
    }
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

struct RGBA: Equatable, CustomStringConvertible {
    var r, g, b, a: UInt8

    func near(_ o: RGBA, _ tolerance: Int = 2) -> Bool {
        abs(Int(r) - Int(o.r)) <= tolerance && abs(Int(g) - Int(o.g)) <= tolerance
            && abs(Int(b) - Int(o.b)) <= tolerance && abs(Int(a) - Int(o.a)) <= tolerance
    }

    var description: String { "(\(r), \(g), \(b), \(a))" }
}

/// An image redrawn as sRGB RGBA8 (premultiplied), indexed with y from the top.
struct Pixels {
    let width: Int, height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        let ctx = Fixture.context(width, height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = Array(UnsafeBufferPointer(start: ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4),
                                          count: width * height * 4))
    }

    subscript(x: Int, y: Int) -> RGBA {
        let i = (y * width + x) * 4
        return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }
}

extension Session {
    /// Replays what OverlayView's DragGesture(minimumDistance: 0) sends:
    /// onChanged at mouse-down and on every move, then onEnded. The first point is where the drag started.
    func drag(through points: [CGPoint]) {
        let a = points[0]
        for p in points { dragChanged(from: a, to: p) }
        dragEnded(from: a, to: points[points.count - 1])
    }

    func drag(_ a: CGPoint, _ b: CGPoint, steps: Int = 4) {
        drag(through: (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        })
    }

    func tap(_ p: CGPoint) { drag(through: [p]) }

    /// One of everything, inside `r`, the way a user would draw it.
    func annotateEverything(in r: CGRect) {
        func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { pt(r.minX + r.width * fx, r.minY + r.height * fy) }
        for (tool, a, b) in [(Tool.arrow, at(0.2, 0.2), at(0.4, 0.4)), (.rect, at(0.5, 0.2), at(0.8, 0.4)),
                             (.highlight, at(0.2, 0.5), at(0.4, 0.6)), (.blur, at(0.5, 0.5), at(0.8, 0.7))] {
            self.tool = tool
            drag(a, b)
        }
        tool = .pen
        drag(through: (0...40).map { i in at(0.2 + CGFloat(i) / 200, 0.8 + (i.isMultiple(of: 2) ? 0 : 0.05)) })
        tool = .step
        tap(at(0.85, 0.25))
        tool = .text
        tap(at(0.55, 0.85))
        draft = "Hello"
        commitText()
        tool = nil
    }
}

/// Deterministic generator so fuzz failures reproduce.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Runs `body`, prints how long it took (grep the test log for "TIMING").
@discardableResult
func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = ContinuousClock.now
    let result = try body()
    print("TIMING \(label): \((ContinuousClock.now - start).formatted(.units(allowed: [.seconds, .milliseconds], fractionalPart: .show(length: 1))))")
    return result
}

/// Current physical footprint of the test host, in MB.
func footprintMB() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(task_self_trap(), task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
}

/// Renders any view offscreen the way the window server would draw it, at the main screen's backing scale.
func snapshot(_ view: some View, size: CGSize) -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}
