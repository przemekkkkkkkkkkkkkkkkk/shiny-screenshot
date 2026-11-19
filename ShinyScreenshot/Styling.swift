import SwiftUI

/// Where the background comes from.
enum FillSource: String, Codable, CaseIterable, Identifiable {
    case backdrop, custom, desktop, desktopGlass, image
    var id: Self { self }
}

enum GradientKind: String, Codable, CaseIterable, Identifiable {
    case mesh = "Mesh", linear = "Linear", radial = "Glow", conic = "Conic", solid = "Solid"
    var id: Self { self }
}

/// A background made from up to three colours: picked by hand, or found in the screenshot.
struct CustomGradient: Codable, Hashable {
    var kind = GradientKind.mesh
    var colors = [0xF472B6, 0x818CF8, 0xFDE68A]
    /// Degrees, clockwise from pointing up.
    var angle: Double = 135

    var isLight: Bool { colors.map(luminance).reduce(0, +) / Double(max(colors.count, 1)) > 0.45 }

    @ViewBuilder var view: some View {
        let c = colors.map(Color.init(hex:))
        switch kind {
        case .mesh:
            let a = c[0], b = c[min(1, c.count - 1)], d = c[min(2, c.count - 1)]
            MeshGradient(width: 3, height: 3,
                         points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                         colors: [a, b, d, b, d, a, d, a, b])
        case .linear:
            let r = (angle - 90) * .pi / 180, dx = cos(r) / 2, dy = sin(r) / 2
            LinearGradient(colors: c, startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
        case .radial:
            EllipticalGradient(colors: c, center: UnitPoint(x: 0.5, y: 0.4), startRadiusFraction: 0, endRadiusFraction: 0.75)
        case .conic:
            AngularGradient(colors: c + [c[0]], center: .center, angle: .degrees(angle - 90))
        case .solid:
            c[0]
        }
    }
}

/// The look of the ring around the shot, after Shots.so.
enum ShotLook: String, Codable, CaseIterable, Identifiable {
    case plain = "Default", glass = "Glass", glassDark = "Glass dark", liquid = "Liquid"
    case inset = "Inset", insetDark = "Inset dark", outline = "Outline", border = "Border"
    var id: Self { self }

    /// Some looks need a ring to be seen at all.
    func ring(_ inset: CGFloat) -> CGFloat {
        switch self {
        case .plain, .outline: inset
        case .border: max(inset, 6)
        default: max(inset, 10)
        }
    }
}

enum ShadowLook: String, Codable, CaseIterable, Identifiable {
    case none = "None", soft = "Soft", spread = "Spread", hug = "Hug", adaptive = "Adaptive", float = "Float", hard = "Hard", glow = "Glow"
    var id: Self { self }
}

/// Window or device drawn around the shot.
enum WindowFrame: String, Codable, CaseIterable, Identifiable {
    case none = "None", mac = "macOS", macDark = "macOS dark", safari = "Safari", chrome = "Chrome", arc = "Arc"
    case windows = "Windows", macbook = "MacBook", iphone = "iPhone", ipad = "iPad"
    var id: Self { self }

    /// Room the frame takes around the shot: top, left, bottom, right.
    var chrome: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        switch self {
        case .none: (0, 0, 0, 0)
        case .mac, .macDark: (28, 0, 0, 0)
        case .safari, .chrome: (40, 0, 0, 0)
        case .windows: (32, 0, 0, 0)
        case .arc: (8, 8, 8, 8)
        case .macbook: (14, 14, 34, 14)
        case .iphone: (14, 14, 14, 14)
        case .ipad: (20, 20, 20, 20)
        }
    }

    var isDevice: Bool { self == .macbook || self == .iphone || self == .ipad }
    var hasAddress: Bool { self == .safari || self == .chrome }
}

enum ShotLayout: String, Codable, CaseIterable, Identifiable {
    case single = "Single", duo = "Duo", stack = "Stack"
    var id: Self { self }
}

enum Tilt: String, Codable, CaseIterable, Identifiable {
    case flat = "Flat", left = "Left", right = "Right", lean = "Lean", iso = "Iso"
    var id: Self { self }

    /// Rotation about x and y, in degrees, and a turn in the picture plane.
    var angles: (x: Double, y: Double, z: Double) {
        switch self {
        case .flat: (0, 0, 0)
        case .left: (5, 16, 0)
        case .right: (5, -16, 0)
        case .lean: (20, 0, 0)
        case .iso: (50, 0, -32)
        }
    }
}

/// Where the shot sits when the canvas has room to spare.
enum Placement: String, Codable, CaseIterable, Identifiable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
    var id: Self { self }

    var unit: CGPoint {
        let i = Placement.allCases.firstIndex(of: self)!
        return CGPoint(x: CGFloat(i % 3) / 2, y: CGFloat(i / 3) / 2)
    }
}

/// Canvas sizes named after where they get posted.
enum Platform: String, Codable, CaseIterable, Identifiable {
    case x = "X post", instagram = "Instagram", story = "Story", linkedin = "LinkedIn", dribbble = "Dribbble"
    case productHunt = "Product Hunt", pinterest = "Pinterest", appStore = "App Store", openGraph = "Open Graph", youtube = "YouTube"
    var id: Self { self }

    var pixels: CGSize {
        switch self {
        case .x: CGSize(width: 1600, height: 900)
        case .instagram: CGSize(width: 1080, height: 1350)
        case .story: CGSize(width: 1080, height: 1920)
        case .linkedin: CGSize(width: 1200, height: 627)
        case .dribbble: CGSize(width: 1600, height: 1200)
        case .productHunt: CGSize(width: 1270, height: 760)
        case .pinterest: CGSize(width: 1000, height: 1500)
        case .appStore: CGSize(width: 1290, height: 2796)
        case .openGraph: CGSize(width: 1200, height: 630)
        case .youtube: CGSize(width: 1280, height: 720)
        }
    }
}

enum Pattern: String, Codable, CaseIterable, Identifiable {
    case none = "None", dots = "Dots", grid = "Grid", lines = "Lines", waves = "Waves"
    var id: Self { self }
}

enum LightScene: String, Codable, CaseIterable, Identifiable {
    case none = "None", window = "Window", blinds = "Blinds"
    var id: Self { self }
}

enum Shapes: String, Codable, CaseIterable, Identifiable {
    case none = "None", orbs = "Orbs", rings = "Rings"
    var id: Self { self }
}

enum VFX: String, Codable, CaseIterable, Identifiable {
    case none = "None", vhs = "VHS", glitch = "Glitch"
    var id: Self { self }
}

enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: Self { self }
}

nonisolated enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", heic = "HEIC"
    var id: Self { self }
    var ext: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
}

enum ExportSize: String, Codable, CaseIterable, Identifiable {
    case native = "Auto", x1 = "1x", x2 = "2x", uhd = "4K"
    var id: Self { self }

    /// Pixels per point for a canvas `width` points wide on a screen of `scale`.
    func scale(screen scale: CGFloat, width: CGFloat) -> CGFloat {
        switch self {
        case .native: scale
        case .x1: 1
        case .x2: 2
        case .uhd: 3840 / max(width, 1)
        }
    }
}

/// Camera moves for the video export, after Shots.so.
enum Motion: String, Codable, CaseIterable, Identifiable {
    case zoom = "Zoom in", pan = "Pan", parallax = "Parallax", float = "Float", reveal = "Reveal", orbit = "Orbit"
    var id: Self { self }
}

extension Style {
    /// Width over height the canvas is held to, if any: a custom size, then a platform, then a ratio.
    var aspect: CGFloat? {
        if let c = customSize, c.width > 0, c.height > 0 { return c.width / c.height }
        if let p = platform { return p.pixels.width / p.pixels.height }
        return ratio.value
    }

    /// Dark text and marks suit this background.
    var isLightFill: Bool {
        switch fill {
        case .backdrop: backdrop.isLight
        case .custom: gradient.isLight
        case .desktop, .desktopGlass, .image: false
        }
    }

    /// The first colour of the fill, for glows and adaptive shadows.
    var keyColor: Int {
        switch fill {
        case .custom: gradient.colors.first ?? 0x6366F1
        case .backdrop: backdrop.keyColor
        default: 0x3B5B8C
        }
    }

    var ringWidth: CGFloat { shotLook.ring(inset) }

    /// Picks a preset, keeping what it doesn't set: whether the background is on, and the words.
    mutating func adopt(_ preset: Style) {
        let keep = (enabled, eyebrow, title, subtitle)
        self = preset
        (enabled, eyebrow, title, subtitle) = keep
    }
}

/// Saved looks: ten that ship, plus the ones you save.
struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var style: Style

    static func == (a: Preset, b: Preset) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    @MainActor static let builtIn: [Preset] = {
        @MainActor func make(_ name: String, _ change: (inout Style) -> Void) -> Preset {
            var s = Style()
            s.enabled = true
            change(&s)
            return Preset(name: name, style: s)
        }
        return [
            make("Launch") { $0.backdrop = .dusk; $0.frame = .mac; $0.shadowLook = .float; $0.shadow = 0.5; $0.ratio = .wide; $0.padding = 64 },
            make("Clean doc") { $0.backdrop = .paper; $0.shotLook = .outline; $0.shadow = 0.25; $0.ratio = .portrait; $0.pattern = .dots; $0.patternAmount = 0.15 },
            make("Neon night") { $0.backdrop = .neon; $0.shotLook = .glass; $0.shadowLook = .glow; $0.ratio = .wide; $0.tilt = .left; $0.pattern = .grid; $0.patternAmount = 0.12; $0.padding = 80 },
            make("Brutal") { $0.backdrop = .sun; $0.shotLook = .border; $0.shadowLook = .hard; $0.shadow = 0.2; $0.ratio = .square; $0.radius = 4; $0.padding = 56 },
            make("Launch post") { $0.backdrop = .peach; $0.frame = .safari; $0.platform = .productHunt; $0.padding = 56 },
            make("Peek") { $0.backdrop = .lagoon; $0.frame = .safari; $0.shadowLook = .float; $0.shadow = 0.5; $0.platform = .dribbble; $0.bleed = true; $0.placement = .bottom },
            make("Editorial") { $0.backdrop = .cream; $0.shadow = 0.3; $0.ratio = .portrait; $0.noise = 0.25; $0.apply(.editorial) },
            make("Isometric") { $0.backdrop = .pastel; $0.frame = .iphone; $0.shadowLook = .float; $0.shadow = 0.45; $0.ratio = .square; $0.tilt = .iso; $0.padding = 40 },
            make("Wallpaper") { $0.backdrop = .silk; $0.shotLook = .glass; $0.shadowLook = .float; $0.shadow = 0.5; $0.ratio = .wide; $0.padding = 72 },
            make("Blueprint") { $0.backdrop = .navy; $0.shotLook = .outline; $0.shadowLook = .none; $0.ratio = .wide; $0.tilt = .right; $0.pattern = .grid; $0.patternAmount = 0.3; $0.padding = 72 },
        ]
    }()

    /// Saved in UserDefaults; a preset this version can't read is dropped.
    static var saved: [Preset] {
        get { (UserDefaults.standard.data(forKey: "stylePresets")).flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "stylePresets") }
    }
}

/// Up to three colours that stand out in an image: k-means over a small copy, most colourful first.
nonisolated func dominantColors(_ image: CGImage, count k: Int = 3) -> [Int] {
    let side = 32
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = ctx.data else { return [] }
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let p = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
    var px: [SIMD3<Double>] = []
    for i in 0..<(side * side) where p[i * 4 + 3] > 200 {
        px.append(SIMD3(Double(p[i * 4]), Double(p[i * 4 + 1]), Double(p[i * 4 + 2])))
    }
    guard !px.isEmpty else { return [] }
    // Seeds spread through the pixels sorted by brightness, so the result is the same every time.
    let sorted = px.sorted { $0.sum() < $1.sum() }
    var centers = (0..<k).map { sorted[min(sorted.count - 1, (2 * $0 + 1) * sorted.count / (2 * k))] }
    for _ in 0..<8 {
        var sums = [SIMD3<Double>](repeating: .zero, count: k), counts = [Int](repeating: 0, count: k)
        for v in px {
            let j = centers.indices.min { dist2(v, centers[$0]) < dist2(v, centers[$1]) }!
            sums[j] += v
            counts[j] += 1
        }
        for j in 0..<k where counts[j] > 0 { centers[j] = sums[j] / Double(counts[j]) }
    }
    func saturation(_ v: SIMD3<Double>) -> Double { (v.max() - v.min()) / max(v.max(), 1) }
    return centers.sorted { saturation($0) > saturation($1) }
        .map { Int($0.x.rounded()) << 16 | Int($0.y.rounded()) << 8 | Int($0.z.rounded()) }
}

nonisolated private func dist2(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { let d = a - b; return (d * d).sum() }

/// Eight backgrounds built from a screenshot's colours: soft, dark, linear, glow and so on.
func magicGradients(_ colors: [Int]) -> [CustomGradient] {
    let c = colors.isEmpty ? [0x6366F1, 0xF59E0B, 0xE2E8F0] : colors + Array(repeating: colors[0], count: max(0, 3 - colors.count))
    let (h0, h1) = (hsl(c[0]).h, hsl(c[1]).h)
    return [
        CustomGradient(kind: .mesh, colors: Array(c.prefix(3))),
        CustomGradient(kind: .mesh, colors: [fromHSL(h0, 0.8, 0.82), fromHSL(h1, 0.9, 0.85), 0xF8FAFC]),
        CustomGradient(kind: .mesh, colors: [fromHSL(h0, 0.6, 0.18), fromHSL(h1, 0.8, 0.35), 0x0F172A]),
        CustomGradient(kind: .linear, colors: [c[0], c[1]]),
        CustomGradient(kind: .radial, colors: [fromHSL(h0, 0.85, 0.65), fromHSL(h0, 0.6, 0.25), 0x0B1020]),
        CustomGradient(kind: .conic, colors: [c[0], c[1], fromHSL(h0 + 40, 0.8, 0.7)], angle: 45),
        CustomGradient(kind: .linear, colors: [fromHSL(h1, 0.95, 0.75), fromHSL(h1 + 25, 0.9, 0.6)], angle: 160),
        CustomGradient(kind: .solid, colors: [fromHSL(h0, 0.35, 0.93)]),
    ]
}

/// A random three-colour harmony, for Shuffle in the gradient builder.
func randomGradient(kind: GradientKind) -> CustomGradient {
    let h = Double.random(in: 0..<360)
    let offsets: [[Double]] = [[0, 28, -28], [0, 180, 150], [0, 120, 240]]
    let o = offsets.randomElement()!
    return CustomGradient(kind: kind, colors: o.map { fromHSL(h + $0, 0.7, 0.6) }, angle: .random(in: 0..<360).rounded())
}

nonisolated func hsl(_ hex: Int) -> (h: Double, s: Double, l: Double) {
    let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
    let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
    guard d > 0 else { return (0, 0, l) }
    var h = mx == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
    h *= 60
    if h < 0 { h += 360 }
    return (h, d / (1 - abs(2 * l - 1)), l)
}

nonisolated func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> Int {
    let h = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    func f(_ n: Double) -> Int {
        let k = (n + h / 30).truncatingRemainder(dividingBy: 12), a = s * min(l, 1 - l)
        return Int((255 * (l - a * max(-1, min(k - 3, 9 - k, 1)))).rounded())
    }
    return f(0) << 16 | f(8) << 8 | f(4)
}

/// Text in a screenshot that shouldn't be shared: emails, card numbers, IP addresses, phone numbers and API keys.
nonisolated func sensitiveRanges(in s: String) -> [Range<String.Index>] {
    let patterns = [
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,                                  // email
        #"\b(?:\d[ -]?){13,19}\b"#,                                                  // card number
        #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,                                             // IPv4
        #"\+?\d{1,3}[ .-]?\(?\d{2,4}\)?[ .-]?\d{3,4}[ .-]?\d{3,4}\b"#,               // phone
        #"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9…]{6,}"#,                           // Stripe
        #"\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{10,}"#,                      // GitHub
        #"\bAKIA[0-9A-Z]{16}\b"#,                                                    // AWS
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,                                          // Slack
        #"\b(?=[A-Za-z0-9_\-]*\d)(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{32,}\b"#, // long token
    ]
    var found: [Range<String.Index>] = []
    for p in patterns {
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            if let r = Range(m.range, in: s), !found.contains(where: { $0.overlaps(r) }) { found.append(r) }
        }
    }
    return found
}

/// How many pixel rows and columns on each side are plain background: the colour of the top-left corner, give or take
/// `tolerance` per channel. Nil when the edges aren't plain or the whole image is.
nonisolated func plainMargins(_ image: CGImage, tolerance: Int = 10) -> (top: Int, left: Int, bottom: Int, right: Int)? {
    let w = image.width, h = image.height
    guard w > 2, h > 2, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = ctx.data else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    // The bitmap's first row is the top of the image.
    func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
    let bg = at(0, 0)
    func plain(_ x: Int, _ y: Int) -> Bool {
        let i = at(x, y)
        return (0..<4).allSatisfy { abs(Int(p[i + $0]) - Int(p[bg + $0])) <= tolerance }
    }
    var top = 0
    while top < h, (0..<w).allSatisfy({ plain($0, top) }) { top += 1 }
    guard top < h else { return nil }
    var bottom = 0
    while (0..<w).allSatisfy({ plain($0, h - 1 - bottom) }) { bottom += 1 }
    let rows = top..<(h - bottom)
    var left = 0
    while rows.allSatisfy({ plain(left, $0) }) { left += 1 }
    var right = 0
    while rows.allSatisfy({ plain(w - 1 - right, $0) }) { right += 1 }
    return (top, left, bottom, right)
}
