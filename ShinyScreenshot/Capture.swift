import AppKit
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

enum Capture {
    /// The screen frozen at the moment of capture. Selecting and marking up happen on this still image,
    /// so nothing on screen can change underneath the selection.
    struct Frozen: Sendable {
        let image: CGImage
        let scale: CGFloat
        /// Display size in points.
        let size: CGSize
        /// On-screen windows, front to back, for click-to-select.
        let windows: [Window]
    }

    struct Window: Sendable {
        let id: CGWindowID
        /// Display points, top-left origin. May hang off the screen.
        let frame: CGRect
    }

    /// One window captured on its own: nothing in front of it, and see-through rounded corners.
    struct WindowShot: Sendable {
        let image: CGImage
        let pixelated: CGImage
        /// Where the window sits, in display points.
        let frame: CGRect
        /// The selection it was taken for; the shot shows only while the selection still matches.
        let selection: CGRect
    }

    @concurrent
    nonisolated static func freeze(displayID: CGDirectDisplayID, scale: CGFloat) async throws -> Frozen {
        let (display, image) = try await shoot(displayID: displayID, scale: scale)
        // Pixelating a 6K screen takes ~100 ms, so the blur copy is made after the overlay is up (Session.preparePixelated).
        return Frozen(image: image,
                      scale: scale,
                      size: CGSize(width: display.width, height: display.height),
                      windows: windows(on: display.frame, excluding: ProcessInfo.processInfo.processIdentifier))
    }

    /// Part of a display, in display points, without this app's windows. For scrolling capture.
    @concurrent
    nonisolated static func area(_ r: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        try await shoot(displayID: displayID, scale: scale, area: r).1
    }

    private nonisolated static func shoot(displayID: CGDirectDisplayID, scale: CGFloat, area: CGRect? = nil) async throws -> (SCDisplay, CGImage) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display,
                                     excludingApplications: content.applications.filter { $0.processID == pid },
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        let size = area?.size ?? CGSize(width: display.width, height: display.height)
        if let area { config.sourceRect = area }
        config.width = Int((size.width * scale).rounded())
        config.height = Int((size.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return (display, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
    }

    /// The window alone, as it is now, without its shadow. Nil if it has closed.
    @concurrent
    nonisolated static func window(_ w: Window, for selection: CGRect, scale: CGFloat) async throws -> WindowShot? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == w.id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let k = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * k).rounded())
        config.height = Int((filter.contentRect.height * k).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return WindowShot(image: image, pixelated: pixelate(image, scale: scale) ?? grey, frame: w.frame, selection: selection)
    }

    /// If pixelation ever fails, blur covers with flat grey rather than showing what it should hide.
    nonisolated static let grey: CGImage = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return ctx.makeImage()!
    }()

    /// Pixelates in 12-point blocks, then scales each block's brightness by a random 0.92–1.08. Plain pixelation of known
    /// text can be reversed by pixelating guesses and comparing blocks (Depix); the noise breaks that match.
    /// `seed` picks the noise; the same seed gives the same noise, so remaking a session's blur copy can't be averaged out.
    nonisolated static func pixelate(_ image: CGImage, scale: CGFloat, seed: CGPoint = randomSeed()) -> CGImage? {
        let input = CIImage(cgImage: image)
        let block = 12 * scale
        func pixellate(_ image: CIImage?) -> CIImage? {
            let f = CIFilter.pixellate()
            f.inputImage = image
            f.scale = Float(block)
            return f.outputImage
        }
        // The generator is deterministic, so a random offset makes every capture's noise different.
        let random = CIFilter.randomGenerator().outputImage?
            .transformed(by: CGAffineTransform(translationX: seed.x, y: seed.y))
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: block, y: block))
        let amount: CGFloat = 0.08
        let noise = CIFilter.colorMatrix()
        noise.inputImage = random
        noise.rVector = CIVector(x: 2 * amount, y: 0, z: 0, w: 0)
        noise.gVector = CIVector(x: 2 * amount, y: 0, z: 0, w: 0)
        noise.bVector = CIVector(x: 2 * amount, y: 0, z: 0, w: 0)
        noise.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        noise.biasVector = CIVector(x: 1 - amount, y: 1 - amount, z: 1 - amount, w: 1)
        let tint = CIFilter.multiplyCompositing()
        tint.inputImage = noise.outputImage
        tint.backgroundImage = pixellate(input.clampedToExtent())
        // Pixelating again keeps every block one flat colour even where the noise grid and block grid don't line up.
        guard let output = pixellate(tint.outputImage)?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }

    nonisolated static func randomSeed() -> CGPoint {
        CGPoint(x: CGFloat.random(in: 0..<10_000).rounded(), y: CGFloat.random(in: 0..<10_000).rounded())
    }

    /// Windows from CGWindowList (front to back, top-left origin), with frames converted to display points.
    nonisolated static func windows(on display: CGRect, excluding pid: pid_t) -> [Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let screen = CGRect(origin: .zero, size: display.size)
        return list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  w[kCGWindowOwnerPID as String] as? pid_t != pid,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            let local = r.offsetBy(dx: -display.minX, dy: -display.minY)
            let visible = local.intersection(screen)
            return visible.width > 40 && visible.height > 40 ? Window(id: id, frame: local) : nil
        }
    }
}
