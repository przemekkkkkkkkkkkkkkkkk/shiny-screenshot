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

enum Ratio: String, CaseIterable, Identifiable {
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

struct Style {
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
enum TextFont: String, CaseIterable, Identifiable {
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

enum TextWeight: String, CaseIterable, Identifiable {
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

enum TextAlign: String, CaseIterable, Identifiable {
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
enum Heading: String, CaseIterable, Identifiable {
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

private struct HeadingView: View {
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

enum Backdrop: String, CaseIterable, Identifiable {
    case silk, prism, solstice, boreal
    case aurora, peach, lagoon, dusk, matcha, holo, ember, glacier, graphite, paper, ink, clear

    var id: Self { self }
    var name: String { self == .clear ? "Transparent" : rawValue.capitalized }
    /// Takes dark text; everything else takes white.
    var isLight: Bool { [.prism, .peach, .matcha, .holo, .glacier, .paper, .clear].contains(self) }

    @ViewBuilder var view: some View {
        switch self {
        case .aurora: mesh(0x6EE7B7, 0x4F46E5, 0x818CF8, 0x22D3EE, 0x312E81, 0xA78BFA, 0xC084FC, 0x22D3EE, 0x312E81)
        case .peach: mesh(0xFDE68A, 0xFECDD3, 0xFDA4AF, 0xFDBA74, 0xFBCFE8, 0xF9A8D4, 0xFDBA74, 0xF472B6, 0xF472B6)
        case .lagoon: mesh(0x67E8F9, 0x38BDF8, 0x3B82F6, 0x22D3EE, 0x2563EB, 0x1D4ED8, 0x06B6D4, 0x0EA5E9, 0x1E40AF)
        case .dusk: mesh(0x2E1065, 0x4C1D95, 0x7C3AED, 0x7C3AED, 0xC026D3, 0xF97316, 0xF97316, 0xFB923C, 0xFDE047)
        case .matcha: mesh(0xECFCCB, 0xD9F99D, 0xBEF264, 0xD9F99D, 0xA3E635, 0x86EFAC, 0xBEF264, 0x4ADE80, 0x22C55E)
        case .holo: mesh(0xF5D0FE, 0xA5B4FC, 0x67E8F9, 0xFDE68A, 0xF0ABFC, 0xA5F3FC, 0xD9F99D, 0xFBCFE8, 0xC4B5FD)
        case .ember: mesh(0x1C0A05, 0x450A0A, 0x1C0A05, 0x7F1D1D, 0x431407, 0x2A0E06, 0xEA580C, 0xF97316, 0x9A3412)
        case .glacier:
            LinearGradient(colors: [Color(hex: 0xE0F2FE), Color(hex: 0xF8FAFC), Color(hex: 0xDBEAFE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .graphite: mesh(0x52525B, 0x3F3F46, 0x27272A, 0x3F3F46, 0x27272A, 0x18181B, 0x27272A, 0x18181B, 0x09090B)
        case .paper: Color(hex: 0xF4F4F5)
        case .ink: Color(hex: 0x0F172A)
        case .clear: Color.clear
        case .silk, .prism, .solstice, .boreal:
            GeometryReader { geometry in
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
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

private func mesh(_ colors: Int...) -> MeshGradient {
    MeshGradient(width: 3, height: 3,
                 points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                 colors: colors.map(Color.init(hex:)))
}

/// The selected part of the frozen screen with its annotations, at selection size.
struct ShotView: View {
    let s: Session

    var body: some View {
        // Read observed state here, not inside the Canvas closure, so changes redraw.
        let sel = s.selection, annotations = s.annotations, editing = s.editingText
        let full = s.bounds
        let image = Image(decorative: s.image, scale: s.scale)
        let pixelated = Image(decorative: s.pixelated, scale: s.scale)
        Canvas { ctx, _ in
            ctx.translateBy(x: -sel.minX, y: -sel.minY)
            ctx.draw(image, in: full)
            for a in annotations where a.id != editing {
                draw(a, in: ctx, pixelated: pixelated, full: full)
            }
        }
        .frame(width: sel.width, height: sel.height)
    }
}

/// What gets exported: the shot, plus background, padding, corners and shadow when enabled.
struct ComposedView: View {
    let s: Session

    var body: some View {
        let style = s.style, size = s.canvas, origin = s.shotOrigin
        ZStack(alignment: .topLeading) {
            if style.enabled { style.backdrop.view.frame(width: size.width, height: size.height) }
            ShotView(s: s)
                .clipShape(RoundedRectangle(cornerRadius: style.enabled ? style.radius : 0, style: .continuous))
                .shadow(color: .black.opacity(style.enabled ? style.shadow : 0), radius: 26, y: 14)
                .offset(x: origin.x, y: origin.y)
            if let h = s.heading {
                let t = s.textOrigin
                HeadingView(h: h).offset(x: t.x, y: t.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
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
        let text = ctx.resolve(Text(a.text).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(a.color == .mark ? .black : .white))
        let t = text.measure(in: CGSize(width: 4000, height: 400))
        let r = CGRect(x: p[0].x, y: p[0].y - t.height / 2 - 5, width: t.width + 18, height: t.height + 10)
        ctx.drawLayer { l in
            l.addFilter(lift)
            l.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(a.color))
        }
        ctx.draw(text, at: CGPoint(x: r.midX, y: r.midY))
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
