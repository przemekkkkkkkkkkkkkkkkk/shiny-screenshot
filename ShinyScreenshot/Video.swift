import AVFoundation
import CoreImage
import ScreenCaptureKit
import SwiftUI

/// Videos: a still with a camera move (Motion), a screen recording (ScreenRecorder), and a recording with its background (Styled).
enum Video {
    /// Where the camera is at `t` (0…1) for a move, on a canvas this size. Parallax moves the background less than the shot.
    nonisolated static func pose(_ m: Motion, t: Double, canvas: CGSize) -> MotionPose {
        let e = t * t * (3 - 2 * t), w = canvas.width, h = canvas.height, wave = sin(t * 2 * .pi)
        var p = MotionPose()
        switch m {
        case .zoom:
            p.scale = 0.86 + 0.14 * e
            p.backgroundScale = 1.1 - 0.1 * e
        case .pan:
            let dx = w * 0.08 * (e - 0.5)
            p.offset = CGSize(width: -dx, height: 0)
            p.backgroundScale = 1.12
            p.backgroundOffset = CGSize(width: -dx * 0.35, height: 0)
            p.textOffset = CGSize(width: -dx * 0.7, height: 0)
        case .parallax:
            p.rotationY = 10 * wave
            p.rotationX = 4 * cos(t * 2 * .pi)
            p.offset = CGSize(width: wave * w * 0.02, height: 0)
            p.backgroundScale = 1.1
            p.backgroundOffset = CGSize(width: -wave * w * 0.015, height: 0)
            p.textOffset = CGSize(width: wave * w * 0.01, height: 0)
        case .float:
            p.offset = CGSize(width: 0, height: wave * h * 0.02)
            p.rotationX = wave * 3
            p.backgroundScale = 1.04
        case .reveal:
            p.offset = CGSize(width: 0, height: (1 - e) * h * 0.55)
            p.scale = 0.92 + 0.08 * e
            p.textOffset = CGSize(width: 0, height: (1 - e) * h * 0.08)
        case .orbit:
            p.rotationY = -22 + 44 * e
            p.scale = 0.9
            p.backgroundScale = 1.1
            p.backgroundOffset = CGSize(width: (e - 0.5) * w * 0.04, height: 0)
        }
        return p
    }

    /// Pixel size for a video of `size` points at `scale`, no bigger than 4K and even on both sides, as H.264 needs.
    nonisolated static func pixels(_ size: CGSize, scale: CGFloat, limit: CGFloat = 3840) -> (w: Int, h: Int, scale: CGFloat) {
        let k = min(scale, limit / max(size.width, size.height, 1))
        return (Int(size.width * k / 2) * 2, Int(size.height * k / 2) * 2, k)
    }

    /// Renders the session's still with its camera move to a 60 fps MP4.
    static func motion(_ s: Session, to url: URL, progress: @escaping (Double) -> Void) async throws {
        let canvas = s.canvas, fps: Int32 = 60
        let (w, h, k) = pixels(canvas, scale: s.exportScale, limit: 2560)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 12],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(s.style.seconds * Double(fps))
        for i in 0..<frames {
            let pose = Self.pose(s.style.motion, t: Double(i) / Double(max(frames - 1, 1)), canvas: canvas)
            let renderer = ImageRenderer(content: ComposedView(s: s, pose: pose))
            renderer.scale = k
            guard let image = renderer.cgImage, let pool = adaptor.pixelBufferPool, let buffer = Self.buffer(image, pool: pool, w: w, h: h) else { continue }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
            progress(Double(i + 1) / Double(frames))
            await Task.yield()
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func buffer(_ image: CGImage, pool: CVPixelBufferPool, w: Int, h: Int) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let b = out else { return nil }
        CVPixelBufferLockBaseAddress(b, [])
        defer { CVPixelBufferUnlockBaseAddress(b, []) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(b), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return b
    }

    /// The recording with the session's background, frame, text and marks around it, as an MP4.
    /// The background is drawn once; each frame of the recording is placed into the hole left for the shot.
    /// ponytail: flat and single only, so tilt, zoom, duo and stack are left out of videos; per-frame 3D would need Metal.
    static func styled(_ s: Session, to url: URL) async throws {
        guard let source = s.video else { return }
        guard s.style.enabled || !s.annotations.isEmpty else { return try FileManager.default.copyItem(at: source, to: url) }
        let saved = s.style
        s.style.layout = .single; s.style.tilt = .flat; s.style.tiltX = 0; s.style.tiltY = 0; s.style.rotation = 0; s.style.zoom = 1
        s.style.vfx = s.style.vfx == .vhs ? .none : s.style.vfx
        defer { s.style = saved }
        let canvas = s.canvas
        let (w, h, k) = pixels(canvas, scale: max(s.pasteScale ?? s.scale, s.exportScale))
        func plate(_ part: ComposedPart) -> CIImage? {
            let r = ImageRenderer(content: ComposedView(s: s, part: part).frame(width: canvas.width, height: canvas.height))
            r.scale = k
            return r.cgImage.map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(scaleX: CGFloat(w) / CGFloat($0.width), y: CGFloat(h) / CGFloat($0.height))) }
        }
        guard let under = plate(.under), let over = plate(.over) else { throw CocoaError(.fileWriteUnknown) }
        // Where the shot goes, in video pixels with the origin at the bottom left.
        let o = s.style.enabled ? s.shotOrigin : .zero, size = s.selection.size
        let sx = CGFloat(w) / canvas.width, sy = CGFloat(h) / canvas.height
        let hole = CGRect(x: o.x * sx, y: CGFloat(h) - (o.y + size.height) * sy, width: size.width * sx, height: size.height * sy)
        let mask = CIImage(cgImage: holeMask(w: w, h: h, hole: hole, radius: s.style.enabled ? s.style.radius * sx : 0,
                                             topSquare: [.mac, .macDark, .safari, .chrome, .windows].contains(s.style.frame)))
        let asset = AVURLAsset(url: source)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let src = request.sourceImage
            let placed = src.transformed(by: CGAffineTransform(scaleX: hole.width / src.extent.width, y: hole.height / src.extent.height))
                .transformed(by: CGAffineTransform(translationX: hole.minX, y: hole.minY))
            let blended = placed.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: under, kCIInputMaskImageKey: mask])
            request.finish(with: over.composited(over: blended).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)), context: nil)
        }
        composition.renderSize = CGSize(width: w, height: h)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw CocoaError(.fileWriteUnknown) }
        export.videoComposition = composition
        try await export.export(to: url, as: .mp4)
    }

    /// White where the recording shows, black elsewhere. Title-bar frames keep the top corners square.
    nonisolated private static func holeMask(w: Int, h: Int, hole: CGRect, radius r: CGFloat, topSquare: Bool) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        let path = CGMutablePath()
        let r = min(r, hole.width / 2, hole.height / 2)
        path.addRoundedRect(in: hole, cornerWidth: r, cornerHeight: r)
        if topSquare { path.addRect(CGRect(x: hole.minX, y: hole.midY, width: hole.width, height: hole.height / 2)) }
        ctx.addPath(path)
        ctx.fillPath()
        return ctx.makeImage()!
    }

    /// The first frame, to mark up and style the recording on.
    nonisolated static func poster(_ url: URL) async -> CGImage? {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .positiveInfinity
        return try? await g.image(at: .zero).image
    }

    /// A new file in Shot.folder named like the screenshots.
    static func newFile(in dir: URL = Shot.folder, prefix: String = "Shiny Recording") -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "\(prefix) \(f.string(from: .now))"
        var url = dir.appending(path: "\(name).mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appending(path: "\(name) (\(n)).mp4")
            n += 1
        }
        return url
    }
}

/// Records one area of a display to an MP4 at up to 60 fps, with the Mac's sound if asked. Our own panels stay out of it.
nonisolated final class ScreenRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private var stream: SCStream?
    private var started = false
    private let queue = DispatchQueue(label: "ShinyScreenshot.recorder")

    init(area: CGRect, scale: CGFloat, sound: Bool) throws {
        url = FileManager.default.temporaryDirectory.appending(path: "Shiny-\(UUID().uuidString).mp4")
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let (w, h, _) = Video.pixels(area.size, scale: scale, limit: 7680)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(w * h * 10, 2_000_000)],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        if sound {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000,
            ])
            a.expectsMediaDataInRealTime = true
            writer.add(a)
            audio = a
        } else {
            audio = nil
        }
        super.init()
    }

    func start(area: CGRect, displayID: CGDirectDisplayID, scale: CGFloat, cursor: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CocoaError(.featureUnsupported) }
        let pid = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == pid }, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let (w, h, _) = Video.pixels(area.size, scale: scale, limit: 7680)
        config.sourceRect = area
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = cursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.capturesAudio = audio != nil
        config.excludesCurrentProcessAudio = true
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audio != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        self.stream = stream
        try await stream.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        switch type {
        case .screen:
            // Idle frames carry no pixels; only complete ones go in.
            guard let info = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            if !started {
                writer.startSession(atSourceTime: sb.presentationTimeStamp)
                started = true
            }
            if video.isReadyForMoreMediaData { video.append(sb) }
        case .audio:
            if started, let audio, audio.isReadyForMoreMediaData { audio.append(sb) }
        default:
            break
        }
    }

    /// Stops and returns the file, or nil if nothing was recorded.
    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync {
            video.markAsFinished()
            audio?.markAsFinished()
        }
        guard started else { writer.cancelWriting(); return nil }
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Floats under the area while it records: time so far, Stop and Cancel.
struct RecordingBar: View {
    let stop: () -> Void
    let cancel: () -> Void
    @State private var start = Date.now

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 8, height: 8)
            TimelineView(.periodic(from: start, by: 1)) { t in
                let s = Int(t.date.timeIntervalSince(start))
                Text(String(format: "Recording · %d:%02d", s / 60, s % 60))
                    .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                    .frame(minWidth: 120, alignment: .leading)
            }
            Button("Cancel", action: cancel).controlSize(.small)
            Button("Stop", action: stop).controlSize(.small).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.11).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(8)
    }
}

/// Shown while a video renders, then while it is ready: open it, show it in Finder, or copy it.
@Observable
final class VideoJob {
    var progress = 0.0
    var url: URL?
    var failed = false
}

struct VideoCard: View {
    let job: VideoJob
    let poster: NSImage
    let title: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(job.failed ? "Couldn't make the video" : job.url == nil ? "Rendering video…" : title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Image(nsImage: poster).resizable().scaledToFit().frame(width: 276, height: 156)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .overlay { if job.url != nil { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)) } }
                .onTapGesture { if let u = job.url { NSWorkspace.shared.open(u) } }
            if let url = job.url {
                HStack(spacing: 6) {
                    Button("Open", systemImage: "play") { NSWorkspace.shared.open(url) }
                    Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([url as NSURL])
                    }
                }
                .controlSize(.small)
            } else if !job.failed {
                ProgressView(value: job.progress).tint(Color.mark)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Color(white: 0.12).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(20)
        .environment(\.colorScheme, .dark)
    }
}
