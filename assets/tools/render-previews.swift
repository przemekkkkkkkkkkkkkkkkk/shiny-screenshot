// Development-only renderer. Compile alongside Capture, Session, Geometry, Drawing and OverlayView.
// Run in a temporary app bundle containing the built Assets.car. Views are captured from an on-screen window
// (Liquid Glass needs one), so the terminal needs Screen Recording permission.
import AppKit
import SwiftUI

enum OverlayAction { case copy, save, pin, scroll, cancel }
enum CaptureMode: String, Codable { case area, window, again, fullScreen, scrolling }
enum Shot { static let folderName = "Desktop" }

@main
struct AssetPreviews {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let root = URL(filePath: CommandLine.arguments[1])
        let out = root.appending(path: "assets/previews")
        let file = out.appending(path: "sample-screen.png")
        let source = NSImage(contentsOf: file)!
        var rect = CGRect(origin: .zero, size: source.size)
        let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        let session = Session(Capture.Frozen(image: image, scale: 2,
                                            size: CGSize(width: 1000, height: 680), windows: []), displayID: 0)
        session.selection = CGRect(x: 150, y: 135, width: 700, height: 410)
        session.phase = .editing
        session.tool = .arrow
        session.color = .mark
        session.annotations = [Annotation(tool: .arrow, color: .mark,
                                         points: [CGPoint(x: 755, y: 460), CGPoint(x: 665, y: 405)])]
        try save(OverlayView(s: session, act: { _ in }), to: out.appending(path: "in-place.png"))
        session.style.enabled = true
        session.style.padding = 64
        session.style.radius = 16
        session.style.backdrop = .silk
        try save(OverlayView(s: session, act: { _ in }), to: out.appending(path: "background-picker.png"))
        for backdrop in Backdrop.allCases {
            // Render the same constrained tile used by BackgroundPanel and ensure sizing stays fixed.
            let tile = ImageRenderer(content: backdrop.tile.frame(width: 56, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7)))
            tile.scale = 2
            let cg = tile.cgImage!
            precondition(cg.width == 112 && cg.height == 76, "Tile layout escaped its frame")
            session.style.backdrop = backdrop
            let rendered = session.render()!
            precondition(rendered.width == Int(session.canvas.width * 2))
            precondition(rendered.height == Int(session.canvas.height * 2))
            if [.silk, .prism, .solstice, .boreal].contains(backdrop) {
                precondition(NSImage(named: backdrop.name) != nil, "Missing wallpaper asset")
                try write(cg, to: out.appending(path: "tile-\(backdrop.rawValue).png"))
                try write(rendered, to: out.appending(path: "export-\(backdrop.rawValue).png"))
            }
        }
        precondition(NSImage(named: "MenuBarIcon")?.isTemplate == true)
        print("PASS: \(Backdrop.allCases.count) backdrops at fixed 56×38 pt tile / export dimensions; four wallpapers resolve; menu image is template.")
    }

    @MainActor static func save<V: View>(_ view: V, to url: URL) throws {
        // Liquid Glass samples what is behind it, so the view goes in a real on-screen window and the window is
        // captured (the terminal running this needs Screen Recording permission).
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 680)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.level = .floating
        window.setFrameOrigin(CGPoint(x: 40, y: 80))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try capture.run()
        capture.waitUntilExit()
        window.close()
    }

    static func write(_ cg: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
        try srgb.representation(using: .png, properties: [:])!.write(to: url)
    }
}
