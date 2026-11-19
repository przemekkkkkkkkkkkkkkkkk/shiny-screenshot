import SwiftUI

extension Color {
    nonisolated init(hex: Int) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// The capture UI's accent: selection outline, handles, active tool.
    static let mark = Color(hex: 0xFFD60A)
}

let palette: [Color] = [0xFF3B30, 0xFF9F0A, 0xFFD60A, 0x34C759, 0x0A84FF, 0xBF5AF2].map(Color.init(hex:))

enum Ratio: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto", wide = "16:9", portrait = "4:5", square = "1:1", link = "1.91:1"

    var id: Self { self }

    var hint: String {
        switch self {
        case .auto: "Fit the screenshot"
        case .wide: "Slides and video"
        case .portrait: "Portrait posts"
        case .square: "Square posts"
        case .link: "Link previews"
        }
    }

    var value: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16 / 9
        case .portrait: 4 / 5
        case .square: 1
        case .link: 1200 / 630
        }
    }
}

struct Style: Codable {
    var enabled = false
    var backdrop = Backdrop.peach
    var padding: CGFloat = 48
    var radius: CGFloat = 10
    var shadow: CGFloat = 0.35
    var ratio = Ratio.auto
    var eyebrow = ""
    var title = ""
    var subtitle = ""
    var heading = Heading.headline
    var font = TextFont.sans
    var weight = TextWeight.bold
    var align = TextAlign.center
    var below = false
    /// Nil picks dark or white text to suit the backdrop.
    var textColor: Int?
    var textScale: CGFloat = 1
    var textShadow = false

    // Fill
    var fill = FillSource.backdrop
    var gradient = CustomGradient()
    /// A picture you chose, copied into Application Support.
    var imagePath: String?
    var blur: CGFloat = 0
    /// 0…1, film grain over the background.
    var noise: CGFloat = 0
    /// 0.4…1.4.
    var brightness: CGFloat = 1
    var pattern = Pattern.none
    var patternAmount: CGFloat = 0.25
    var light = LightScene.none
    var shapes = Shapes.none
    var vfx = VFX.none
    var vignette = false
    // Shot
    var shotLook = ShotLook.plain
    var inset: CGFloat = 0
    var shadowLook = ShadowLook.soft
    var layout = ShotLayout.single
    var redact = false
    var frame = WindowFrame.none
    var address = "yourapp.com"
    // Canvas
    var platform: Platform?
    /// Pixels; wins over the platform and ratio.
    var customSize: CGSize?
    var autoBalance = false
    var placement = Placement.center
    var bleed = false
    var zoom: CGFloat = 1
    /// Degrees.
    var rotation: CGFloat = 0
    var tilt = Tilt.flat
    var tiltX: CGFloat = 0
    var tiltY: CGFloat = 0
    var canvasRadius: CGFloat = 0
    // Brand
    var watermark = false
    var watermarkText = "@shinyshot"
    var watermarkCorner = Corner.bottomRight
    var watermarkOpacity: CGFloat = 0.85
    var watermarkPill = true
    // Export
    var format = ExportFormat.png
    var size = ExportSize.native
    /// Keeps the padding but leaves it see-through.
    var transparent = false
    var motion = Motion.zoom
    var seconds: Double = 4

    init() {}

    /// Every field falls back to its default, so styles saved by older versions still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Style()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        enabled = v(.enabled, d.enabled); backdrop = v(.backdrop, d.backdrop); padding = v(.padding, d.padding)
        radius = v(.radius, d.radius); shadow = v(.shadow, d.shadow); ratio = v(.ratio, d.ratio)
        eyebrow = v(.eyebrow, d.eyebrow); title = v(.title, d.title); subtitle = v(.subtitle, d.subtitle)
        heading = v(.heading, d.heading); font = v(.font, d.font); weight = v(.weight, d.weight); align = v(.align, d.align)
        below = v(.below, d.below); textColor = v(.textColor, d.textColor); textScale = v(.textScale, d.textScale)
        textShadow = v(.textShadow, d.textShadow)
        fill = v(.fill, d.fill); gradient = v(.gradient, d.gradient); imagePath = v(.imagePath, d.imagePath)
        blur = v(.blur, d.blur); noise = v(.noise, d.noise); brightness = v(.brightness, d.brightness)
        pattern = v(.pattern, d.pattern); patternAmount = v(.patternAmount, d.patternAmount); light = v(.light, d.light)
        shapes = v(.shapes, d.shapes); vfx = v(.vfx, d.vfx); vignette = v(.vignette, d.vignette)
        shotLook = v(.shotLook, d.shotLook); inset = v(.inset, d.inset); shadowLook = v(.shadowLook, d.shadowLook)
        layout = v(.layout, d.layout); redact = v(.redact, d.redact); frame = v(.frame, d.frame); address = v(.address, d.address)
        platform = v(.platform, d.platform); customSize = v(.customSize, d.customSize); autoBalance = v(.autoBalance, d.autoBalance)
        placement = v(.placement, d.placement); bleed = v(.bleed, d.bleed); zoom = v(.zoom, d.zoom); rotation = v(.rotation, d.rotation)
        tilt = v(.tilt, d.tilt); tiltX = v(.tiltX, d.tiltX); tiltY = v(.tiltY, d.tiltY); canvasRadius = v(.canvasRadius, d.canvasRadius)
        watermark = v(.watermark, d.watermark); watermarkText = v(.watermarkText, d.watermarkText)
        watermarkCorner = v(.watermarkCorner, d.watermarkCorner); watermarkOpacity = v(.watermarkOpacity, d.watermarkOpacity)
        watermarkPill = v(.watermarkPill, d.watermarkPill); format = v(.format, d.format); size = v(.size, d.size)
        transparent = v(.transparent, d.transparent); motion = v(.motion, d.motion); seconds = v(.seconds, d.seconds)
    }

    /// Picks a preset and the font, weight and position it comes with; colour, size and shadow stay as chosen.
    mutating func apply(_ h: Heading) {
        heading = h
        font = h == .editorial ? .serif : .sans
        weight = h == .poster ? .black : .bold
        align = h == .editorial ? .leading : .center
        below = h == .caption
    }
}

/// System designs first, then families that ship with macOS.
enum TextFont: String, CaseIterable, Identifiable, Codable {
    case sans = "Sans", rounded = "Rounded", serif = "Serif", mono = "Mono"
    case avenir = "Avenir Next", futura = "Futura", didot = "Didot", georgia = "Georgia"

    var id: Self { self }
    var name: String { self == .avenir ? "Avenir" : rawValue }
    var hint: String { "\(rawValue) title" }

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign? = switch self {
        case .sans: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
        if let design {
            return system.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
        // The family's face nearest the weight; families without that weight fall back to their closest.
        let faces = NSFontDescriptor(fontAttributes: [.family: rawValue]).matchingFontDescriptors(withMandatoryKeys: [.family])
        func distance(_ d: NSFontDescriptor) -> CGFloat {
            let traits = d.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            let italic = ((traits?[.symbolic] as? UInt32) ?? 0) & NSFontDescriptor.SymbolicTraits.italic.rawValue != 0
            return abs(((traits?[.weight] as? CGFloat) ?? 0) - weight.rawValue) + (italic ? 10 : 0)
        }
        return faces.min { distance($0) < distance($1) }.flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }
}

enum TextWeight: String, CaseIterable, Identifiable, Codable {
    case light = "Light", regular = "Regular", bold = "Bold", black = "Black"

    var id: Self { self }
    var hint: String { "\(rawValue) title" }

    var value: NSFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .bold: .bold
        case .black: .black
        }
    }
}

enum TextAlign: String, CaseIterable, Identifiable, Codable {
    case leading = "Left", center = "Centre", trailing = "Right"

    var id: Self { self }
    var hint: String { "Align text \(rawValue.lowercased())" }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Text colours offered beside Auto.
let textColors = [0xFFFFFF, 0x0F172A] + [0xFF3B30, 0xFF9F0A, 0xFFD60A, 0x34C759, 0x0A84FF, 0xBF5AF2]

/// Title and description layouts, after App Store screenshots, editorial cards and captions.
enum Heading: String, CaseIterable, Identifiable, Codable {
    case headline = "Headline", editorial = "Editorial", poster = "Poster", caption = "Caption"

    var id: Self { self }

    var hint: String {
        switch self {
        case .headline: "Bold title above, centred"
        case .editorial: "Serif title above, left-aligned"
        case .poster: "Heavy capitals above"
        case .caption: "Small caption below"
        }
    }

    /// Title and description sizes at 900 pt wide, and the description's weight.
    var sizes: (title: CGFloat, body: CGFloat, bodyWeight: NSFont.Weight) {
        switch self {
        case .headline: (40, 20, .regular)
        case .editorial: (42, 19, .regular)
        case .poster: (54, 20, .medium)
        case .caption: (18, 15, .regular)
        }
    }
}

/// Eyebrow, title and description measured for one text width.
struct HeadingLayout {
    struct Line {
        let text: String
        let font: NSFont
        let kern: CGFloat
        let opacity: Double
    }

    let style: Style
    let lines: [Line]
    let width: CGFloat
    /// Between lines, and between the text and the shot.
    let spacing: CGFloat, gap: CGFloat
    let height: CGFloat

    init?(_ style: Style, width: CGFloat) {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = clean(style.title)
        guard !title.isEmpty || !clean(style.subtitle).isEmpty else { return nil }
        // Sized to the text width, so a title reads the same on a small crop and on a full screen.
        let k = min(max(width / 900, 0.6), 2.5) * style.textScale
        let sizes = style.heading.sizes
        let body = NSFont.systemFont(ofSize: sizes.body * k, weight: sizes.bodyWeight)
        lines = [
            Line(text: clean(style.eyebrow).uppercased(), font: .systemFont(ofSize: sizes.body * 0.68 * k, weight: .semibold),
                 kern: 1.6 * k, opacity: 0.6),
            Line(text: style.heading == .poster ? title.uppercased() : title,
                 font: style.font.font(size: sizes.title * k, weight: style.weight.value), kern: 0, opacity: 1),
            Line(text: clean(style.subtitle), font: body, kern: 0, opacity: 0.72),
        ].filter { !$0.text.isEmpty }
        self.style = style
        self.width = width
        spacing = body.pointSize * 0.5
        gap = sizes.title * k * (style.below ? 0.9 : 1.1)
        height = lines.reduce(spacing * CGFloat(lines.count - 1)) { sum, l in
            sum + ceil(NSAttributedString(string: l.text, attributes: [.font: l.font, .kern: l.kern])
                .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }
    }
}

struct HeadingView: View {
    let h: HeadingLayout

    var body: some View {
        let align = h.style.align
        let color = h.style.textColor ?? (h.style.backdrop.isLight ? 0x0F172A : 0xFFFFFF)
        VStack(alignment: align.horizontal, spacing: h.spacing) {
            ForEach(h.lines.indices, id: \.self) { i in
                let l = h.lines[i]
                Text(l.text).font(Font(l.font as CTFont)).kerning(l.kern).opacity(l.opacity)
            }
        }
        .multilineTextAlignment(align.text)
        .foregroundStyle(Color(hex: color))
        .shadow(color: .black.opacity(h.style.textShadow ? 0.45 : 0), radius: h.spacing, y: h.spacing / 4)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: h.width, alignment: Alignment(horizontal: align.horizontal, vertical: .top))
    }
}

/// The background gallery, in the order the picker shows it.
enum Backdrop: String, CaseIterable, Identifiable, Codable {
    // Wallpapers
    case silk, prism, solstice, boreal
    // Mesh
    case aurora, peach, lagoon, dusk, matcha, holo, ember, graphite
    case sorbet, nebula, tropic, berry, ocean, sunrise, lavender, mint, cosmos, coral
    case forest, candy, volcano, arctic, midnight, rosegold, neon
    // Gradients
    case glacier, azure, flamingo, lime, royal, sunset, citrus, grape, steel, seafoam, blush, copper, emerald, cherry, sand, twilight
    case spectrum, pastel
    // Glow
    case nova, bloom, amber, firefly, pearl, halo
    // Solid
    case paper, ink, snow, onyx, slate, cream, navy, pine, wine, lilac, butter, tangerine, rose, sun, clear

    enum Group: String, CaseIterable, Identifiable {
        case wallpaper = "Wallpapers", mesh = "Mesh", gradient = "Gradients", glow = "Glow", solid = "Solid"
        var id: Self { self }
        var backdrops: [Backdrop] { Backdrop.allCases.filter { $0.group == self } }
    }

    private enum Paint {
        case image, mesh([Int]), linear([Int]), angular([Int]), radial([Int]), solid(Int), clear
    }

    var id: Self { self }
    var name: String { self == .clear ? "Transparent" : self == .rosegold ? "Rose Gold" : rawValue.capitalized }

    var group: Group {
        switch paint {
        case .image: .wallpaper
        case .mesh: .mesh
        case .linear, .angular: .gradient
        case .radial: .glow
        case .solid, .clear: .solid
        }
    }

    /// The first colour, for glows and adaptive shadows.
    var keyColor: Int {
        switch paint {
        case .image: self == .prism ? 0xC4B5FD : 0x3B5B8C
        case .clear: 0x888888
        case let .solid(c): c
        case let .mesh(c), let .linear(c), let .angular(c), let .radial(c): c[c.count / 2]
        }
    }

    /// Takes dark text; everything else takes white. Judged by the colours' mean luminance.
    var isLight: Bool { colors.map(luminance).reduce(0, +) / Double(colors.count) > 0.45 }

    /// The colours it is painted with; wallpapers stand in as one.
    var colors: [Int] {
        switch paint {
        case .image: self == .prism ? [0xFFFFFF] : [0]
        case .clear: [0xFFFFFF]
        case let .solid(c): [c]
        case let .mesh(c), let .linear(c), let .angular(c), let .radial(c): c
        }
    }

    private var paint: Paint {
        switch self {
        case .silk, .prism, .solstice, .boreal: .image
        case .aurora: .mesh([0x6EE7B7, 0x4F46E5, 0x818CF8, 0x22D3EE, 0x312E81, 0xA78BFA, 0xC084FC, 0x22D3EE, 0x312E81])
        case .peach: .mesh([0xFDE68A, 0xFECDD3, 0xFDA4AF, 0xFDBA74, 0xFBCFE8, 0xF9A8D4, 0xFDBA74, 0xF472B6, 0xF472B6])
        case .lagoon: .mesh([0x67E8F9, 0x38BDF8, 0x3B82F6, 0x22D3EE, 0x2563EB, 0x1D4ED8, 0x06B6D4, 0x0EA5E9, 0x1E40AF])
        case .dusk: .mesh([0x2E1065, 0x4C1D95, 0x7C3AED, 0x7C3AED, 0xC026D3, 0xF97316, 0xF97316, 0xFB923C, 0xFDE047])
        case .matcha: .mesh([0xECFCCB, 0xD9F99D, 0xBEF264, 0xD9F99D, 0xA3E635, 0x86EFAC, 0xBEF264, 0x4ADE80, 0x22C55E])
        case .holo: .mesh([0xF5D0FE, 0xA5B4FC, 0x67E8F9, 0xFDE68A, 0xF0ABFC, 0xA5F3FC, 0xD9F99D, 0xFBCFE8, 0xC4B5FD])
        case .ember: .mesh([0x1C0A05, 0x450A0A, 0x1C0A05, 0x7F1D1D, 0x431407, 0x2A0E06, 0xEA580C, 0xF97316, 0x9A3412])
        case .graphite: .mesh([0x52525B, 0x3F3F46, 0x27272A, 0x3F3F46, 0x27272A, 0x18181B, 0x27272A, 0x18181B, 0x09090B])
        case .sorbet: .mesh([0xFBCFE8, 0xF9A8D4, 0xFDBA74, 0xFDE68A, 0xFCA5A5, 0xFB7185, 0xFED7AA, 0xFDA4AF, 0xF472B6])
        case .nebula: .mesh([0x0F0A2E, 0x3B0764, 0x1E1B4B, 0x6D28D9, 0xDB2777, 0x312E81, 0x1E1B4B, 0x9333EA, 0x0F0A2E])
        case .tropic: .mesh([0x2DD4BF, 0x34D399, 0xFDE047, 0x14B8A6, 0x10B981, 0xFACC15, 0x0D9488, 0x059669, 0xF59E0B])
        case .berry: .mesh([0x4A044E, 0x831843, 0xBE185D, 0x701A75, 0xDB2777, 0xF43F5E, 0x3B0764, 0x9D174D, 0xE11D48])
        case .ocean: .mesh([0x082F49, 0x0C4A6E, 0x075985, 0x0E7490, 0x0369A1, 0x0284C7, 0x155E75, 0x0891B2, 0x22D3EE])
        case .sunrise: .mesh([0xFEF3C7, 0xFDE68A, 0xFCA5A5, 0xFDBA74, 0xFB923C, 0xF87171, 0xF472B6, 0xEC4899, 0xDB2777])
        case .lavender: .mesh([0xEDE9FE, 0xDDD6FE, 0xE9D5FF, 0xC4B5FD, 0xD8B4FE, 0xF5D0FE, 0xA78BFA, 0xC084FC, 0xF0ABFC])
        case .mint: .mesh([0xECFDF5, 0xD1FAE5, 0xCCFBF1, 0xA7F3D0, 0x99F6E4, 0xBAE6FD, 0x6EE7B7, 0x5EEAD4, 0x7DD3FC])
        case .cosmos: .mesh([0x020617, 0x1E1B4B, 0x0F172A, 0x312E81, 0x4338CA, 0x1E3A8A, 0x0F172A, 0x6366F1, 0x020617])
        case .coral: .mesh([0xFFE4E6, 0xFECDD3, 0xFED7AA, 0xFDA4AF, 0xFB7185, 0xFDBA74, 0xF43F5E, 0xFB923C, 0xF97316])
        case .forest: .mesh([0x052E16, 0x14532D, 0x064E3B, 0x166534, 0x15803D, 0x047857, 0x022C22, 0x065F46, 0x14532D])
        case .candy: .mesh([0xA5F3FC, 0xF0ABFC, 0xFDE68A, 0xC4B5FD, 0xF9A8D4, 0xBAE6FD, 0xFBCFE8, 0xA7F3D0, 0xDDD6FE])
        case .volcano: .mesh([0x18181B, 0x450A0A, 0x7C2D12, 0x3F0A0A, 0xB91C1C, 0xEA580C, 0x7F1D1D, 0xF97316, 0xFBBF24])
        case .arctic: .mesh([0xF0F9FF, 0xE0F2FE, 0xF1F5F9, 0xBAE6FD, 0xE2E8F0, 0xC7D2FE, 0x93C5FD, 0xCBD5E1, 0xA5B4FC])
        case .midnight: .mesh([0x0B1020, 0x111827, 0x1E293B, 0x1E1B4B, 0x172554, 0x0F172A, 0x312E81, 0x1E3A8A, 0x0B1020])
        case .rosegold: .mesh([0xFFF1F2, 0xFFE4E6, 0xFEF3C7, 0xFBCFE8, 0xFECACA, 0xFDE68A, 0xF9A8D4, 0xFDA4AF, 0xFCD34D])
        case .neon: .mesh([0x0F172A, 0x7C3AED, 0x0F172A, 0xEC4899, 0x0F172A, 0x22D3EE, 0x0F172A, 0x84CC16, 0x0F172A])
        case .glacier: .linear([0xE0F2FE, 0xF8FAFC, 0xDBEAFE])
        case .azure: .linear([0x38BDF8, 0x818CF8])
        case .flamingo: .linear([0xF472B6, 0xFB923C])
        case .lime: .linear([0xA3E635, 0x22D3EE])
        case .royal: .linear([0x1E3A8A, 0x7C3AED])
        case .sunset: .linear([0xF59E0B, 0xEF4444, 0xBE185D])
        case .citrus: .linear([0xFDE047, 0xFB923C])
        case .grape: .linear([0x7E22CE, 0xDB2777])
        case .steel: .linear([0x64748B, 0x1E293B])
        case .seafoam: .linear([0x99F6E4, 0x93C5FD])
        case .blush: .linear([0xFCE7F3, 0xE0E7FF])
        case .copper: .linear([0x7C2D12, 0xD97706])
        case .emerald: .linear([0x064E3B, 0x10B981])
        case .cherry: .linear([0x881337, 0xF43F5E])
        case .sand: .linear([0xFAF5EB, 0xE7D7C1])
        case .twilight: .linear([0x0F172A, 0x4C1D95, 0xDB2777])
        case .spectrum: .angular([0xF87171, 0xFBBF24, 0x34D399, 0x38BDF8, 0xA78BFA, 0xF472B6, 0xF87171])
        case .pastel: .angular([0xFECACA, 0xFDE68A, 0xBBF7D0, 0xBAE6FD, 0xDDD6FE, 0xFBCFE8, 0xFECACA])
        case .nova: .radial([0x3B82F6, 0x1E1B4B, 0x0B1020])
        case .bloom: .radial([0xF472B6, 0x701A75, 0x1E0A1E])
        case .amber: .radial([0xFBBF24, 0x9A3412, 0x1C1007])
        case .firefly: .radial([0x34D399, 0x065F46, 0x03140E])
        case .pearl: .radial([0xFFFFFF, 0xF1F5F9, 0xCBD5E1])
        case .halo: .radial([0xFEF9C3, 0xFDBA74, 0xF472B6])
        case .paper: .solid(0xF4F4F5)
        case .ink: .solid(0x0F172A)
        case .snow: .solid(0xFFFFFF)
        case .onyx: .solid(0x09090B)
        case .slate: .solid(0x334155)
        case .cream: .solid(0xFAF7F0)
        case .navy: .solid(0x1E3A8A)
        case .pine: .solid(0x14532D)
        case .wine: .solid(0x7F1D1D)
        case .lilac: .solid(0xEDE9FE)
        case .butter: .solid(0xFEF9C3)
        case .tangerine: .solid(0xF97316)
        case .rose: .solid(0xFB7185)
        case .sun: .solid(0xFACC15)
        case .clear: .clear
        }
    }

    @ViewBuilder var view: some View {
        switch paint {
        case .image:
            GeometryReader { geometry in
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        case let .mesh(c):
            MeshGradient(width: 3, height: 3,
                         points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                         colors: c.map(Color.init(hex:)))
        case let .linear(c):
            LinearGradient(colors: c.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
        case let .angular(c):
            AngularGradient(colors: c.map(Color.init(hex:)), center: .center)
        case let .radial(c):
            // Sized to the canvas, so the glow reads the same in a tile and on a full screen.
            EllipticalGradient(colors: c.map(Color.init(hex:)), center: .center, startRadiusFraction: 0, endRadiusFraction: 0.75)
        case let .solid(c): Color(hex: c)
        case .clear: Color.clear
        }
    }

    /// Swatch for the picker; transparent shows a checkerboard.
    @ViewBuilder var tile: some View {
        if self == .clear {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for x in stride(from: 0, to: size.width, by: 6) {
                    for y in stride(from: 0, to: size.height, by: 6) where (Int(x / 6) + Int(y / 6)).isMultiple(of: 2) {
                        ctx.fill(Path(CGRect(x: x, y: y, width: 6, height: 6)), with: .color(Color(white: 0.85)))
                    }
                }
            }
        } else {
            view
        }
    }
}

/// WCAG relative luminance of an sRGB colour.
nonisolated func luminance(_ hex: Int) -> Double {
    [16, 8, 0].map { Double((hex >> $0) & 0xFF) / 255 }
        .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        .enumerated().map { [0.2126, 0.7152, 0.0722][$0] * $1 }.reduce(0, +)
}

/// The selected part of the frozen screen with its annotations, at selection size.
struct ShotView: View {
    let s: Session
    /// Off for the layer drawn over a video: only the marks.
    var drawsImage = true

    var body: some View {
        // Read observed state here, not inside the Canvas closure, so changes redraw.
        let sel = s.selection, annotations = s.annotations.filter { $0.id != s.editingText }
        let window = s.activeWindowShot, hidden = s.hiddenAreas
        let full = window?.frame ?? s.bounds
        let image = Image(decorative: window?.image ?? s.image, scale: s.scale)
        // Until the blur copy is ready, blur shows flat grey, never the pixels it hides.
        let pixelated = Image(decorative: window?.pixelated ?? s.pixelated ?? Capture.grey, scale: s.scale)
        Canvas { ctx, _ in
            ctx.translateBy(x: -sel.minX, y: -sel.minY)
            if drawsImage { ctx.draw(image, in: full) }
            // Spotlights dim everything else, so they go under the other marks. Source-atop keeps see-through window corners clear.
            let spots = annotations.filter { $0.tool == .spotlight }
            if !spots.isEmpty {
                var dim = ctx
                dim.blendMode = .sourceAtop
                dim.drawLayer { l in
                    l.fill(Path(sel), with: .color(.black.opacity(0.5)))
                    l.blendMode = .clear
                    for a in spots { l.fill(Path(roundedRect: a.box, cornerRadius: 8), with: .color(.black)) }
                }
            }
            for a in annotations where a.tool != .spotlight {
                draw(a, in: ctx, pixelated: pixelated, full: full)
            }
            // Emails, keys and the like the background panel was asked to hide.
            for r in hidden {
                ctx.drawLayer { l in
                    l.clip(to: Path(roundedRect: r, cornerRadius: 4))
                    l.draw(pixelated, in: full)
                }
            }
        }
        .frame(width: sel.width, height: sel.height)
    }
}

private func draw(_ a: Annotation, in ctx: GraphicsContext, pixelated: Image, full: CGRect) {
    let p = a.points
    let lift = GraphicsContext.Filter.shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    switch a.tool {
    case .arrow:
        guard let end = p.last, p[0].distance(to: end) > 1 else { return }
        ctx.drawLayer { l in
            l.addFilter(lift)
            l.fill(arrowPath(from: p[0], to: end), with: .color(a.color))
        }
    case .rect:
        ctx.drawLayer { l in
            l.addFilter(lift)
            l.stroke(Path(roundedRect: a.box, cornerRadius: 6), with: .color(a.color), lineWidth: 4)
        }
    case .highlight:
        var l = ctx
        l.blendMode = .multiply
        l.fill(Path(roundedRect: a.box, cornerRadius: 3), with: .color(Color.mark.opacity(0.55)))
    case .spotlight:
        break
    case .blur:
        ctx.drawLayer { l in
            l.clip(to: Path(roundedRect: a.box, cornerRadius: 4))
            l.draw(pixelated, in: full)
        }
    case .pen:
        var path = Path()
        path.addLines(p)
        ctx.drawLayer { l in
            l.addFilter(lift)
            l.stroke(path, with: .color(a.color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    case .step:
        let r = CGRect(x: p[0].x - 13, y: p[0].y - 13, width: 26, height: 26)
        ctx.drawLayer { l in
            l.addFilter(lift)
            l.fill(Path(ellipseIn: r), with: .color(a.color))
            l.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: 2)
        }
        ctx.draw(Text("\(a.number)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white), at: p[0])
    case .text:
        let r = a.labelFrame
        let text = Text(a.text).font(Font(a.font as CTFont)).foregroundStyle(a.textColor)
        let origin = CGPoint(x: r.minX + a.inset.width, y: r.minY + a.inset.height)
        ctx.drawLayer { l in
            if a.filled {
                l.addFilter(lift)
                l.fill(Path(roundedRect: r, cornerRadius: a.cornerRadius), with: .color(a.color))
            } else {
                // Two dark halos keep coloured text readable on any background.
                l.addFilter(a.halo)
                l.addFilter(a.halo)
            }
            l.draw(text, at: origin, anchor: .topLeading)
        }
    }
}

/// Text label sizes, stepped through by the smaller and larger buttons.
let labelSizes: [CGFloat] = [12, 15, 20, 28, 40]

extension Annotation {
    var font: NSFont { .systemFont(ofSize: size, weight: filled ? .semibold : .bold) }
    /// Between a label's text and its edge.
    var inset: CGSize { CGSize(width: size * 0.6, height: size / 3) }
    var cornerRadius: CGFloat { size * 0.47 }
    var textColor: Color { filled ? (color == .mark ? .black : .white) : color }
    var halo: GraphicsContext.Filter { .shadow(color: .black.opacity(0.75), radius: max(1.5, size / 10)) }

    /// A text label's box: starts at the click with its first line centred on it, and grows down for more lines.
    var labelFrame: CGRect {
        func measure(_ s: String) -> CGSize {
            NSAttributedString(string: s, attributes: [.font: font])
                .boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        }
        let t = measure(text.isEmpty ? " " : text), line = measure(" ").height
        return CGRect(x: points[0].x, y: points[0].y - line / 2 - inset.height,
                      width: ceil(t.width) + 2 * inset.width, height: ceil(t.height) + 2 * inset.height)
    }
}

/// A tapered arrow: thin at the tail, wide near the head.
func arrowPath(from a: CGPoint, to b: CGPoint) -> Path {
    let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 1)
    let ux = dx / len, uy = dy / len, px = -uy, py = ux
    let head = min(22, len * 0.5)
    let neck = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
    func side(_ o: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: o.x + px * k, y: o.y + py * k) }
    var path = Path()
    path.addLines([side(a, 1.3), side(neck, 3.5), side(neck, 10.5), b, side(neck, -10.5), side(neck, -3.5), side(a, -1.3)])
    path.closeSubpath()
    return path
}
