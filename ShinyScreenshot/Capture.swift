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
        /// Same image, pixelated, for the blur tool.
        let pixelated: CGImage
        let scale: CGFloat
        /// Display size in points.
        let size: CGSize
        /// On-screen window frames in display points, front to back, for click-to-select.
        let windows: [CGRect]
    }

    @concurrent
    nonisolated static func freeze(displayID: CGDirectDisplayID, scale: CGFloat) async throws -> Frozen {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display,
                                     excludingApplications: content.applications.filter { $0.processID == pid },
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Frozen(image: image,
                      pixelated: pixelate(image, scale: scale) ?? grey,
                      scale: scale,
                      size: CGSize(width: display.width, height: display.height),
                      windows: windowFrames(on: display.frame, excluding: pid))
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
    nonisolated static func pixelate(_ image: CGImage, scale: CGFloat) -> CGImage? {
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
            .transformed(by: CGAffineTransform(translationX: .random(in: 0..<10_000).rounded(), y: .random(in: 0..<10_000).rounded()))
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

    /// Window bounds from CGWindowList (front to back, top-left origin), converted to display points.
    nonisolated static func windowFrames(on display: CGRect, excluding pid: pid_t) -> [CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let screen = CGRect(origin: .zero, size: display.size)
        return list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  w[kCGWindowOwnerPID as String] as? pid_t != pid,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            let local = r.offsetBy(dx: -display.minX, dy: -display.minY).intersection(screen)
            return local.width > 40 && local.height > 40 ? local : nil
        }
    }
}
