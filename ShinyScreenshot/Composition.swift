import SwiftUI

/// One frame of a motion export: how far the camera has moved each layer. Identity for stills.
nonisolated struct MotionPose: Equatable {
    var backgroundScale: CGFloat = 1
    var backgroundOffset = CGSize.zero
    var scale: CGFloat = 1
    var offset = CGSize.zero
    /// Degrees, added to the style's tilt.
    var rotationX: Double = 0
    var rotationY: Double = 0
    var textOffset = CGSize.zero
}

/// Which layers to draw. Video export draws what goes under the moving picture and what goes over it separately.
enum ComposedPart { case all, under, over }

/// What gets exported: the shot, plus background, frame, effects and text when the background is on.
struct ComposedView: View {
    let s: Session
    var pose = MotionPose()
    var part = ComposedPart.all

    var body: some View {
        let style = s.style, size = s.canvas
        let content = ZStack(alignment: .topLeading) {
            if style.enabled {
                if part != .over && !style.transparent {
                    BackgroundLayer(style: style, size: size, desktop: s.desktopImage)
                        .scaleEffect(pose.backgroundScale)
                        .offset(pose.backgroundOffset)
                }
                shots(style)
                if part != .over, let h = s.heading {
                    let t = s.textOrigin
                    HeadingView(h: h).offset(x: t.x + pose.textOffset.width, y: t.y + pose.textOffset.height)
                }
                if part != .under {
                    EffectsLayer(style: style, size: size)
                    if style.watermark { Watermark(style: style, size: size) }
                }
            } else {
                ShotView(s: s, drawsImage: part != .over)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        if style.enabled && style.canvasRadius > 0 {
            content.clipShape(RoundedRectangle(cornerRadius: style.canvasRadius, style: .continuous))
        } else {
            content.clipped()
        }
    }

    /// The main shot, with its copies behind it for the duo and stack layouts.
    @ViewBuilder private func shots(_ style: Style) -> some View {
        let box = s.boxFrame
        if part != .over {
            switch style.layout {
            case .single: EmptyView()
            case .duo:
                placed(FramedShot(s: s, part: part), at: CGPoint(x: box.minX + box.width * 0.75, y: box.minY + box.height * 0.21), scale: 0.86)
            case .stack:
                ForEach([2, 1], id: \.self) { i in
                    placed(FramedShot(s: s, part: part), at: CGPoint(x: box.minX - box.width * 0.05 * CGFloat(i),
                                                                      y: box.minY - box.height * 0.05 * CGFloat(i)), scale: 1)
                        .opacity(1 - 0.25 * Double(i))
                }
            }
            if style.vfx == .vhs {
                placed(FramedShot(s: s, part: part).colorMultiply(.red), at: CGPoint(x: box.minX + 2, y: box.minY), scale: 1)
                    .opacity(0.5).blendMode(.screen)
                placed(FramedShot(s: s, part: part).colorMultiply(.cyan), at: CGPoint(x: box.minX - 2, y: box.minY), scale: 1)
                    .opacity(0.5).blendMode(.screen)
            }
        }
        placed(FramedShot(s: s, part: part), at: box.origin, scale: 1)
    }

    private func placed(_ v: some View, at p: CGPoint, scale k: CGFloat) -> some View {
        v.modifier(ShotTransform(style: s.style, pose: pose))
            .scaleEffect(k, anchor: .topLeading)
            .offset(x: p.x, y: p.y)
    }
}

/// Zoom, turn and tilt, applied only when they change something so a flat shot stays a pixel copy.
private struct ShotTransform: ViewModifier {
    let style: Style
    let pose: MotionPose

    func body(content: Content) -> some View {
        let t = style.tilt.angles
        let rx = t.x + style.tiltX + pose.rotationX, ry = t.y + style.tiltY + pose.rotationY, rz = t.z + style.rotation
        let k = style.zoom * pose.scale * (style.tilt == .iso ? 0.86 : 1)
        if rx == 0, ry == 0, rz == 0, k == 1, pose.offset == .zero {
            content
        } else {
            content
                .rotationEffect(.degrees(rz))
                .rotation3DEffect(.degrees(rx), axis: (1, 0, 0), perspective: 0.5)
                .rotation3DEffect(.degrees(ry), axis: (0, 1, 0), perspective: 0.5)
                .scaleEffect(k)
                .offset(pose.offset)
        }
    }
}

/// The shot inside its window frame and ring, with its shadow.
struct FramedShot: View {
    let s: Session
    var part = ComposedPart.all

    var body: some View {
        let st = s.style, sel = s.shotArea.size, ring = st.ringWidth, ch = st.frame.chrome
        let frameRadius = st.frame.isDevice ? st.radius + max(ch.left, ch.top) : st.radius
        let content: AnyView = part == .under ? AnyView(Color.black) : AnyView(ShotView(s: s, drawsImage: part != .over))
        if part == .over {
            content.frame(width: sel.width, height: sel.height)
                .offset(x: ring + ch.left, y: ring + ch.top)
                .frame(width: s.boxSize.width, height: s.boxSize.height, alignment: .topLeading)
        } else if st.frame == .none && ring == 0 && st.shotLook != .outline {
            // The plain case, exactly as before frames existed.
            content
                .frame(width: sel.width, height: sel.height)
                .clipShape(RoundedRectangle(cornerRadius: st.radius, style: .continuous))
                .modifier(ShotShadow(style: st))
        } else {
            ZStack(alignment: .topLeading) {
                Ring(look: st.shotLook, radius: frameRadius + ring, width: ring, size: s.boxSize)
                ZStack(alignment: .topLeading) {
                    FrameChrome(frame: st.frame, radius: frameRadius, address: st.address,
                                size: CGSize(width: sel.width + ch.left + ch.right, height: sel.height + ch.top + ch.bottom))
                    content
                        .frame(width: sel.width, height: sel.height)
                        .clipShape(screenShape(st))
                        .offset(x: ch.left, y: ch.top)
                }
                .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
                .offset(x: ring, y: ring)
            }
            .frame(width: s.boxSize.width, height: s.boxSize.height, alignment: .topLeading)
            .compositingGroup()
            .modifier(ShotShadow(style: st))
        }
    }

    /// Windows round only their bottom corners under the title bar; devices round all four.
    private func screenShape(_ st: Style) -> UnevenRoundedRectangle {
        let r = st.radius
        switch st.frame {
        case .mac, .macDark, .safari, .chrome, .windows:
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0), style: .continuous)
        case .arc:
            let a = max(r - 4, 0)
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: a, bottomLeading: a, bottomTrailing: a, topTrailing: a), style: .continuous)
        default:
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r), style: .continuous)
        }
    }
}

private struct ShotShadow: ViewModifier {
    let style: Style

    func body(content: Content) -> some View {
        let a = style.shadow
        switch style.shadowLook {
        case .none: content
        case .soft: content.shadow(color: .black.opacity(a), radius: 26, y: 14)
        case .spread: content.shadow(color: .black.opacity(a), radius: 40, y: 24)
        case .hug: content.shadow(color: .black.opacity(a), radius: 2, y: 1).shadow(color: .black.opacity(a * 0.8), radius: 7, y: 4)
        case .adaptive:
            content.shadow(color: Color(hex: fromHSL(hsl(style.keyColor).h, 0.6, 0.22)).opacity(min(1, a * 2)), radius: 34, y: 20)
        case .float: content.shadow(color: .black.opacity(min(1, a * 1.3)), radius: 50, y: 40).shadow(color: .black.opacity(a * 0.6), radius: 12, y: 8)
        case .hard: content.shadow(color: .black.opacity(0.92), radius: 0, x: 10 + a * 20, y: 10 + a * 20)
        case .glow: content.shadow(color: Color(hex: style.keyColor).opacity(0.9), radius: 30 + a * 60)
        }
    }
}

/// The ring between the shot and the background, in one of Shots.so's looks.
private struct Ring: View {
    let look: ShotLook
    let radius: CGFloat
    let width: CGFloat
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            switch look {
            case .plain: shape.fill(.white.opacity(width > 0 ? 0.35 : 0))
            case .glass: shape.fill(.white.opacity(0.26)).overlay(shape.strokeBorder(.white.opacity(0.6), lineWidth: 1))
            case .glassDark: shape.fill(.black.opacity(0.3)).overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
            case .liquid:
                shape.fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3)], startPoint: .top, endPoint: .bottom),
                                                lineWidth: 1.5))
            case .inset: shape.fill(Color(hex: 0xEEF1F5))
            case .insetDark: shape.fill(Color(hex: 0x1C1C20))
            case .outline:
                RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .padding(-7)
            case .border: shape.fill(.white)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A window title bar, a browser bar or a device bezel. The shot is drawn over it.
private struct FrameChrome: View {
    let frame: WindowFrame
    let radius: CGFloat
    let address: String
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch frame {
            case .none: Color.clear
            case .mac, .macDark:
                bar(color: frame == .mac ? 0xECECEE : 0x2A2A2E, line: frame == .mac ? 0xD9D9DD : 0x1C1C1F) { lights }
            case .safari:
                bar(color: 0xF4F4F6, line: 0xE2E2E6) {
                    lights
                    Spacer()
                    pill(fill: Color(hex: 0xE6E6EA))
                    Spacer()
                    Color.clear.frame(width: 52)
                }
            case .chrome:
                bar(color: 0xDEE1E6, line: 0xC9CCD1) {
                    lights
                    pill(fill: .white).padding(.leading, 14)
                }
            case .windows:
                bar(color: 0xF3F3F3, line: 0xE5E5E5) {
                    Spacer()
                    ForEach(["minus", "square", "xmark"], id: \.self) {
                        Image(systemName: $0).font(.system(size: 10, weight: .regular)).foregroundStyle(Color(hex: 0x444444)).frame(width: 36)
                    }
                }
            case .arc:
                LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0xF9A8D4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .macbook:
                VStack(spacing: 0) {
                    Color(hex: 0x111114)
                    LinearGradient(colors: [Color(hex: 0xD9DBE0), Color(hex: 0xA9ACB3)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                }
            case .iphone, .ipad:
                Color(hex: 0x111114).overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color(hex: 0x3A3A40), lineWidth: 1.5))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func bar<C: View>(color: Int, line: Int, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { content() }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: frame.chrome.top - 1)
                .background(Color(hex: color))
            Color(hex: line).frame(height: 1)
            Color.white
        }
    }

    private var lights: some View {
        HStack(spacing: 8) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 12, height: 12) }
        }
    }

    private func pill(fill: Color) -> some View {
        Text(address)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: 0x6B6B73))
            .lineLimit(1)
            .frame(maxWidth: min(size.width * 0.5, 420), minHeight: 24)
            .padding(.horizontal, 10)
            .background(fill, in: Capsule())
    }
}

/// Everything behind the shot: the fill with blur and brightness, then pattern, grain, shapes and vignette.
private struct BackgroundLayer: View {
    let style: Style
    let size: CGSize
    let desktop: NSImage?

    var body: some View {
        ZStack {
            fill
                .frame(width: size.width, height: size.height)
                .modifier(Softened(blur: style.blur + (style.fill == .desktopGlass ? 40 : 0),
                                   saturation: style.fill == .desktopGlass ? 1.6 : 1, brightness: style.brightness))
            if style.pattern != .none { PatternLayer(pattern: style.pattern, amount: style.patternAmount, dark: style.isLightFill) }
            if style.shapes != .none { ShapesLayer(shapes: style.shapes, key: style.keyColor, size: size) }
            if style.noise > 0 {
                Image(decorative: noiseTile, scale: 1).resizable(resizingMode: .tile)
                    .opacity(style.noise).blendMode(.overlay)
            }
            if style.vignette {
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center,
                               startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.75)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder private var fill: some View {
        switch style.fill {
        case .backdrop: style.backdrop.view
        case .custom: style.gradient.view
        case .desktop, .desktopGlass: picture(desktop) ?? AnyView(Backdrop.boreal.view)
        case .image: picture(style.imagePath.flatMap(Pictures.image(at:))) ?? AnyView(Color.gray)
        }
    }

    private func picture(_ image: NSImage?) -> AnyView? {
        image.map { AnyView(Image(nsImage: $0).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()) }
    }
}

private struct Softened: ViewModifier {
    let blur: CGFloat, saturation: Double, brightness: CGFloat

    func body(content: Content) -> some View {
        if blur == 0, saturation == 1, brightness == 1 {
            content
        } else {
            content.blur(radius: blur, opaque: true).saturation(saturation).brightness((brightness - 1) * 0.5)
        }
    }
}

private struct PatternLayer: View {
    let pattern: Pattern
    let amount: CGFloat
    /// Dark marks on a light background.
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let ink = (dark ? Color.black : Color.white)
            switch pattern {
            case .none: break
            case .dots:
                for x in stride(from: 9.0, to: size.width, by: 18) {
                    for y in stride(from: 9.0, to: size.height, by: 18) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)), with: .color(ink.opacity(amount)))
                    }
                }
            case .grid:
                var p = Path()
                for x in stride(from: 0.0, to: size.width, by: 32) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                for y in stride(from: 0.0, to: size.height, by: 32) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(p, with: .color(ink.opacity(amount * 0.6)), lineWidth: 1)
            case .lines:
                var p = Path()
                for x in stride(from: -size.height, to: size.width, by: 12) {
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                ctx.stroke(p, with: .color(ink.opacity(amount * 0.5)), lineWidth: 1)
            case .waves:
                var p = Path()
                let reach = hypot(size.width, size.height)
                for r in stride(from: 16.0, to: reach, by: 16) {
                    p.addEllipse(in: CGRect(x: -r, y: size.height - r, width: 2 * r, height: 2 * r))
                }
                ctx.stroke(p, with: .color(ink.opacity(amount * 0.5)), lineWidth: 1.5)
            }
        }
    }
}

private struct ShapesLayer: View {
    let shapes: Shapes
    let key: Int
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            switch shapes {
            case .none: EmptyView()
            case .orbs:
                orb(d: w * 0.34, second: fromHSL(hsl(key).h + 40, 0.8, 0.6)).offset(x: -w * 0.07, y: -w * 0.12)
                orb(d: w * 0.18, second: fromHSL(hsl(key).h - 30, 0.8, 0.55)).offset(x: w * 0.85, y: h - w * 0.13)
            case .rings:
                ForEach([0.6, 0.9, 1.2], id: \.self) { k in
                    Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
                        .frame(width: w * k, height: w * k)
                        .offset(x: w * (1 - k) / 2, y: h / 2 - w * k / 2)
                }
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func orb(d: CGFloat, second: Int) -> some View {
        Circle()
            .fill(RadialGradient(colors: [.white, Color(hex: key), Color(hex: second)], center: UnitPoint(x: 0.32, y: 0.3),
                                 startRadius: 0, endRadius: d * 0.75))
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.28), radius: 30, y: 24)
    }
}

/// Light through a window or blinds, and VHS or glitch effects, over everything.
private struct EffectsLayer: View {
    let style: Style
    let size: CGSize

    var body: some View {
        ZStack {
            switch style.light {
            case .none: EmptyView()
            case .window:
                Canvas { ctx, s in
                    for (a, b) in [(0.22, 0.34), (0.39, 0.52)] {
                        var p = Path()
                        let slant = s.height * 0.4
                        p.addLines([CGPoint(x: s.width * a, y: 0), CGPoint(x: s.width * b, y: 0),
                                    CGPoint(x: s.width * b - slant, y: s.height), CGPoint(x: s.width * a - slant, y: s.height)])
                        ctx.fill(p, with: .color(.white.opacity(0.22)))
                    }
                }
                .blur(radius: 12).blendMode(.softLight)
            case .blinds:
                Canvas { ctx, s in
                    for y in stride(from: -s.width * 0.2, to: s.height + s.width * 0.2, by: 46) {
                        var p = Path()
                        p.addLines([CGPoint(x: 0, y: y), CGPoint(x: s.width, y: y - s.width * 0.18),
                                    CGPoint(x: s.width, y: y - s.width * 0.18 + 22), CGPoint(x: 0, y: y + 22)])
                        ctx.fill(p, with: .color(.black.opacity(0.22)))
                    }
                }
                .blur(radius: 6).blendMode(.multiply)
            }
            switch style.vfx {
            case .none: EmptyView()
            case .vhs:
                Canvas { ctx, s in
                    var p = Path()
                    for y in stride(from: 0.0, to: s.height, by: 3) { p.addRect(CGRect(x: 0, y: y, width: s.width, height: 1)) }
                    ctx.fill(p, with: .color(.black.opacity(0.18)))
                }
            case .glitch:
                Canvas { ctx, s in
                    for (y, h, c) in [(0.31, 0.02, Color(hex: 0xFF005A).opacity(0.35)), (0.62, 0.015, Color.cyan.opacity(0.3)),
                                      (0.80, 0.01, Color.white.opacity(0.25))] {
                        ctx.fill(Path(CGRect(x: 0, y: s.height * y, width: s.width, height: s.height * h)), with: .color(c))
                    }
                }
                .blendMode(.difference)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private struct Watermark: View {
    let style: Style
    let size: CGSize

    var body: some View {
        let k = min(max(size.width / 900, 0.6), 3)
        let margin = max(12, min(style.padding / 2, 40))
        let alignment: Alignment = switch style.watermarkCorner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
        HStack(spacing: 7 * k) {
            RoundedRectangle(cornerRadius: 6 * k, style: .continuous).fill(Color.mark).frame(width: 18 * k, height: 18 * k)
            Text(style.watermarkText).font(.system(size: 13 * k, weight: .semibold))
        }
        .padding(.horizontal, style.watermarkPill ? 11 * k : 0)
        .padding(.vertical, style.watermarkPill ? 7 * k : 0)
        .foregroundStyle(style.watermarkPill || !style.isLightFill ? .white : Color(hex: 0x0F172A))
        .background(style.watermarkPill ? Color.black.opacity(0.45) : .clear, in: Capsule())
        .opacity(style.watermarkOpacity)
        .padding(margin)
        .frame(width: size.width, height: size.height, alignment: alignment)
    }
}

/// Film grain: random greys, tiled.
private let noiseTile: CGImage = {
    let side = 128
    var bytes = [UInt8](repeating: 255, count: side * side * 4)
    for i in 0..<(side * side) {
        let v = UInt8.random(in: 0...255)
        bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v
    }
    let ctx = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}()

/// Pictures used as backgrounds, loaded once.
enum Pictures {
    private static var cache: [String: NSImage] = [:]

    static func image(at path: String) -> NSImage? {
        if let i = cache[path] { return i }
        let i = NSImage(contentsOfFile: path)
        cache[path] = i
        return i
    }

    /// Where pictures you pick are kept, so a saved style still finds them.
    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "ShinyScreenshot").appending(path: "Backgrounds")
    }

    /// Copies a picture into the app's folder and returns its new path.
    static func keep(_ url: URL) -> String? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appending(path: "\(UUID().uuidString).\(url.pathExtension)")
        return (try? FileManager.default.copyItem(at: url, to: dest)) != nil ? dest.path : nil
    }

    /// The wallpaper of the screen the capture is on.
    static func desktop(for screen: NSScreen?) -> NSImage? {
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return image(at: url.path)
    }
}
