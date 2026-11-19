import SwiftUI

/// The background sidebar: presets on top, then one section at a time from the rail.
struct StylePanel: View {
    @Bindable var s: Session
    let act: (OverlayAction) -> Void
    @State private var section: Section
    @State private var presets = Preset.saved

    init(s: Session, act: @escaping (OverlayAction) -> Void, section: Section = .fill) {
        self.s = s
        self.act = act
        _section = State(initialValue: section)
    }

    enum Section: String, CaseIterable, Identifiable {
        case fill = "Fill", shot = "Shot", frame = "Frame", canvas = "Canvas", effects = "Effects", text = "Text", brand = "Brand", export = "Export"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .fill: "photo"
            case .shot: "square.on.square"
            case .frame: "macwindow"
            case .canvas: "aspectratio"
            case .effects: "sparkles"
            case .text: "character.textbox"
            case .brand: "seal"
            case .export: "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                VStack(spacing: 2) {
                    ForEach(Section.allCases) { sec in
                        Button { section = sec } label: {
                            VStack(spacing: 3) {
                                Image(systemName: sec.symbol).font(.system(size: 15, weight: .medium))
                                Text(sec.rawValue).font(.system(size: 9.5, weight: .semibold))
                            }
                            .frame(width: 52, height: 44)
                            .foregroundStyle(section == sec ? .black : .secondary)
                            .background(section == sec ? Color.mark : .clear, in: RoundedRectangle(cornerRadius: 11))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                }
                .scrollIndicators(.never)
                .frame(width: 64)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { pane }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: 430, height: min(720, s.size.height - 40))
        .background(Color(white: 0.11).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .onChange(of: s.style.redact) { s.detectSensitive() }
        .onAppear { s.detectSensitive() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Style").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Magic", systemImage: "wand.and.stars") { magic() }
                    .help("A random look in your screenshot's colours")
                Button("Save", systemImage: "plus") {
                    var p = Preset(name: "Look \(presets.count + 1)", style: s.style)
                    p.style.eyebrow = ""; p.style.title = ""; p.style.subtitle = ""
                    presets.append(p)
                    Preset.saved = presets
                }
                .help("Save this look as a preset")
            }
            .controlSize(.small)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Preset.builtIn + presets) { p in
                        Button { s.style.adopt(p.style) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                PresetThumb(style: p.style).frame(width: 88, height: 52)
                                Text(p.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                            }
                            .frame(width: 88)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if presets.contains(p) {
                                Button("Delete") { presets.removeAll { $0 == p }; Preset.saved = presets }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(14)
    }

    /// A random built-in look, filled with the screenshot's colours.
    private func magic() {
        let look = Preset.builtIn.randomElement()!
        s.style.adopt(look.style)
        s.style.fill = .custom
        s.style.gradient = magicGradients(s.magicColors).randomElement()!
    }

    @ViewBuilder private var pane: some View {
        switch section {
        case .fill: FillPane(s: s, act: act)
        case .shot: shotPane
        case .frame: framePane
        case .canvas: canvasPane
        case .effects: effectsPane
        case .text: textPane
        case .brand: brandPane
        case .export: exportPane
        }
    }

    // MARK: Shot

    @ViewBuilder private var shotPane: some View {
        Group2("Style") {
            Tiles(ShotLook.allCases, columns: 4, selection: $s.style.shotLook, label: \.rawValue) { look in
                RoundedRectangle(cornerRadius: 5).fill(look == .insetDark || look == .glassDark ? Color(white: 0.3) : .white.opacity(0.85))
                    .padding(4)
                    .background(look == .plain ? .clear : look == .border ? .white : .white.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                    .frame(width: 28, height: 20)
            }
        }
        Group2("Inset") { LabeledSlider(label: "Inset", value: $s.style.inset, range: 0...48, text: "\(Int(s.style.inset))") }
        Group2("Corners") {
            HoverReveal {
                Chips(options: [CGFloat(0), 12, 24], selection: $s.style.radius,
                      label: { $0 == 0 ? "Sharp" : $0 == 12 ? "Curved" : "Round" }, hint: { "\(Int($0)) pt corners" })
            } more: {
                LabeledSlider(label: "Radius", value: $s.style.radius, range: 0...40, text: "\(Int(s.style.radius))")
            }
        }
        Group2("Shadow") {
            HoverReveal {
                Tiles(ShadowLook.allCases, columns: 4, selection: $s.style.shadowLook, label: \.rawValue) { look in
                    RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 20, height: 15)
                        .shadow(color: look == .glow ? Color.mark : look == .adaptive ? .purple : .black.opacity(look == .none ? 0 : 0.6),
                                radius: look == .hard ? 0 : look == .hug ? 1.5 : 5, x: look == .hard ? 3 : 0, y: look == .hard ? 3 : 3)
                }
            } more: {
                LabeledSlider(label: "Opacity", value: $s.style.shadow, range: 0...1, text: "\(Int(s.style.shadow * 100))%")
            }
        }
        Group2("Layout") { Chips(options: ShotLayout.allCases, selection: $s.style.layout, label: \.rawValue, hint: { "\($0.rawValue) shot" }) }
        Group2("Privacy") {
            Toggle("Hide emails, keys and card numbers", isOn: $s.style.redact).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
            if s.style.redact {
                Text(s.redactions.isEmpty ? "Nothing sensitive found." : "\(s.redactions.count) hidden.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Frame

    @ViewBuilder private var framePane: some View {
        Group2("Window or device") {
            Tiles(WindowFrame.allCases, columns: 4, selection: $s.style.frame, label: \.rawValue) { f in FrameIcon(frame: f) }
        }
        if s.style.frame.hasAddress {
            Group2("Address bar") { PanelField(prompt: "yourapp.com", text: $s.style.address) }
        }
    }

    // MARK: Canvas

    @ViewBuilder private var canvasPane: some View {
        Group2("Size") {
            let auto = s.style.platform == nil && s.style.customSize == nil
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                SizeTile(title: "Auto", detail: s.style.ratio == .auto ? "Fit" : s.style.ratio.rawValue, ratio: nil, on: auto) {
                    s.style.platform = nil; s.style.customSize = nil
                }
                ForEach(Platform.allCases) { p in
                    SizeTile(title: p.rawValue, detail: "\(Int(p.pixels.width))×\(Int(p.pixels.height))",
                             ratio: p.pixels.width / p.pixels.height, on: s.style.platform == p && s.style.customSize == nil) {
                        s.style.platform = p; s.style.customSize = nil
                    }
                }
                SizeTile(title: "Custom", detail: "W × H", ratio: nil, on: s.style.customSize != nil) {
                    s.style.customSize = s.style.customSize ?? CGSize(width: 1600, height: 900)
                }
            }
            if let c = s.style.customSize {
                HStack {
                    NumberField(value: Binding { c.width } set: { s.style.customSize?.width = max($0, 16) })
                    Text("×").foregroundStyle(.secondary)
                    NumberField(value: Binding { c.height } set: { s.style.customSize?.height = max($0, 16) })
                }
            }
            if auto {
                Chips(options: Ratio.allCases, selection: $s.style.ratio, label: \.rawValue, hint: \.hint)
            }
        }
        Group2("Balance") {
            Toggle("Auto balance", isOn: $s.style.autoBalance).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
                .help("Trims the plain margin around what's in the shot so it's the same on every side, and centres it")
        }
        Group2("Space and position") {
            LabeledSlider(label: "Padding", value: $s.style.padding, range: 0...200, text: "\(Int(s.style.padding))")
            if !s.style.autoBalance {
                HStack {
                    Text("Position").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    PlacementGrid(selection: $s.style.placement)
                }
                Toggle("Bleed off the edge", isOn: $s.style.bleed).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
            }
        }
        Group2("Transform") {
            LabeledSlider(label: "Zoom", value: $s.style.zoom, range: 0.5...1.3, text: "\(Int((s.style.zoom * 100).rounded()))%")
            LabeledSlider(label: "Rotate", value: $s.style.rotation, range: -20...20, text: "\(Int(s.style.rotation))°")
            Chips(options: Tilt.allCases, selection: $s.style.tilt, label: \.rawValue, hint: { "\($0.rawValue) perspective" })
            LabeledSlider(label: "Tilt X", value: $s.style.tiltX, range: -35...35, text: "\(Int(s.style.tiltX))°")
            LabeledSlider(label: "Tilt Y", value: $s.style.tiltY, range: -35...35, text: "\(Int(s.style.tiltY))°")
        }
        Group2("Canvas corners") {
            LabeledSlider(label: "Corners", value: $s.style.canvasRadius, range: 0...48, text: "\(Int(s.style.canvasRadius))")
        }
    }

    // MARK: Effects

    @ViewBuilder private var effectsPane: some View {
        Group2("Background") {
            LabeledSlider(label: "Blur", value: $s.style.blur, range: 0...40, text: "\(Int(s.style.blur))")
            LabeledSlider(label: "Noise", value: $s.style.noise, range: 0...1, text: "\(Int(s.style.noise * 100))%")
            LabeledSlider(label: "Brightness", value: $s.style.brightness, range: 0.4...1.4, text: "\(Int((s.style.brightness * 100).rounded()))%")
        }
        Group2("Pattern") {
            HoverReveal {
                Chips(options: Pattern.allCases, selection: $s.style.pattern, label: \.rawValue, hint: { "\($0.rawValue) pattern" })
            } more: {
                LabeledSlider(label: "Amount", value: $s.style.patternAmount, range: 0.05...0.6, text: "\(Int(s.style.patternAmount / 0.6 * 100))%")
            }
        }
        Group2("Light") { Chips(options: LightScene.allCases, selection: $s.style.light, label: \.rawValue, hint: { "\($0.rawValue) light" }) }
        Group2("Shapes") { Chips(options: Shapes.allCases, selection: $s.style.shapes, label: \.rawValue, hint: { "\($0.rawValue) behind the shot" }) }
        Group2("VFX") { Chips(options: VFX.allCases, selection: $s.style.vfx, label: \.rawValue, hint: { "\($0.rawValue) effect" }) }
        Toggle("Vignette", isOn: $s.style.vignette).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
    }

    // MARK: Text

    @ViewBuilder private var textPane: some View {
        Group2("Title") {
            VStack(spacing: 4) {
                PanelField(prompt: "Label, like NEW or STEP 1", text: $s.style.eyebrow)
                PanelField(prompt: "Title", text: $s.style.title)
                PanelField(prompt: "Description", text: $s.style.subtitle)
            }
            Chips(options: Heading.allCases, selection: Binding { s.style.heading } set: { s.style.apply($0) },
                  label: \.rawValue, hint: \.hint)
            if s.heading != nil {
                Chips(options: Array(TextFont.allCases.prefix(4)), selection: $s.style.font, label: \.name, hint: \.hint)
                Chips(options: Array(TextFont.allCases.suffix(4)), selection: $s.style.font, label: \.name, hint: \.hint)
                Chips(options: TextWeight.allCases, selection: $s.style.weight, label: \.rawValue, hint: \.hint)
                HStack(spacing: 8) {
                    Chips(options: [false, true], selection: $s.style.below,
                          label: { $0 ? "Below" : "Above" }, hint: { $0 ? "Text under the shot" : "Text over the shot" })
                    Chips(options: TextAlign.allCases, selection: $s.style.align, label: \.rawValue, hint: \.hint)
                }
                ColorRow(selection: $s.style.textColor)
                LabeledSlider(label: "Text size", value: $s.style.textScale, range: 0.6...1.8,
                              text: "\(Int((s.style.textScale * 100).rounded()))%")
                Toggle("Text shadow", isOn: $s.style.textShadow)
                    .toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
            }
        }
    }

    // MARK: Brand

    @ViewBuilder private var brandPane: some View {
        Group2("Watermark") {
            Toggle("Show watermark", isOn: $s.style.watermark).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
            if s.style.watermark {
                PanelField(prompt: "@handle or yoursite.com", text: $s.style.watermarkText)
                HStack {
                    Chips(options: [true, false], selection: $s.style.watermarkPill, label: { $0 ? "Pill" : "Plain" }, hint: { $0 ? "On a dark pill" : "Text only" })
                    Spacer(minLength: 16)
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        GridRow { corner(.topLeft); corner(.topRight) }
                        GridRow { corner(.bottomLeft); corner(.bottomRight) }
                    }
                }
                LabeledSlider(label: "Opacity", value: $s.style.watermarkOpacity, range: 0.2...1, text: "\(Int(s.style.watermarkOpacity * 100))%")
            }
        }
    }

    private func corner(_ c: Corner) -> some View {
        Button { s.style.watermarkCorner = c } label: {
            RoundedRectangle(cornerRadius: 4).fill(s.style.watermarkCorner == c ? Color.mark : .white.opacity(0.14)).frame(width: 18, height: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Export

    @ViewBuilder private var exportPane: some View {
        Group2("Image") {
            Chips(options: ExportFormat.allCases, selection: $s.style.format, label: \.rawValue, hint: { "Save as \($0.rawValue)" })
            Chips(options: ExportSize.allCases, selection: $s.style.size, label: \.rawValue, hint: { $0 == .native ? "The screen's own resolution" : "\($0.rawValue) export" })
            Toggle("Leave the background see-through", isOn: $s.style.transparent).toggleStyle(.switch).controlSize(.mini).tint(Color.mark)
            HStack {
                Text("Size").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                let k = s.exportScale, c = s.canvas
                Text("\(Int((c.width * k).rounded())) × \(Int((c.height * k).rounded()))")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
            HStack(spacing: 6) {
                Button("Copy", systemImage: "doc.on.doc") { act(.copy) }
                Button("Save", systemImage: "square.and.arrow.down") { act(.save) }
                Button("Pin", systemImage: "pin") { act(.pin) }
            }
            .controlSize(.small)
        }
        Group2(s.video == nil ? "Video with motion" : "Recording") {
            if s.video == nil {
                Chips(options: Array(Motion.allCases.prefix(3)), selection: $s.style.motion, label: \.rawValue, hint: { "\($0.rawValue) camera move" })
                Chips(options: Array(Motion.allCases.suffix(3)), selection: $s.style.motion, label: \.rawValue, hint: { "\($0.rawValue) camera move" })
                LabeledSlider(label: "Length", value: Binding { CGFloat(s.style.seconds) } set: { s.style.seconds = Double($0.rounded()) },
                              range: 2...10, text: "\(Int(s.style.seconds)) s")
                Button("Save Video", systemImage: "film") { act(.video) }.controlSize(.small)
                    .help("A 60 fps MP4 of this image with the camera move, saved to \(Shot.folderName)")
            } else {
                Text("Copy and Save export the recording with this background, frame and text.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The Fill section: the library, colours from the shot, your own gradient, or a picture.
private struct FillPane: View {
    @Bindable var s: Session
    let act: (OverlayAction) -> Void
    @State private var source = Source.library
    @State private var query = ""
    @State private var hue: HueFamily?
    @State private var mood: Bool?
    @AppStorage("favoriteBackdrops") private var favoritesRaw = "dusk,aurora,silk"
    @AppStorage("recentBackdrops") private var recentsRaw = ""

    enum Source: String, CaseIterable { case library = "Library", magic = "Magic", gradient = "Gradient", image = "Image" }

    private var favorites: [Backdrop] { favoritesRaw.split(separator: ",").compactMap { Backdrop(rawValue: String($0)) } }
    private var recents: [Backdrop] { recentsRaw.split(separator: ",").compactMap { Backdrop(rawValue: String($0)) } }

    var body: some View {
        Chips(options: Source.allCases, selection: $source, label: \.rawValue, hint: { "Backgrounds: \($0.rawValue)" })
        switch source {
        case .library: library
        case .magic: magic
        case .gradient: gradient
        case .image: images
        }
    }

    @ViewBuilder private var library: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(Backdrop.allCases.count) backgrounds", text: $query).textFieldStyle(.plain)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        HStack(spacing: 6) {
            ForEach([HueFamily?.none] + HueFamily.allCases.map(Optional.some), id: \.self) { h in
                Button { hue = h } label: {
                    Circle().fill(h.map { AnyShapeStyle(Color(hex: $0.swatch)) } ?? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(hue == h ? Color.mark : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .help(h?.rawValue ?? "All colours")
            }
            Spacer()
            Chips(options: [Bool?.none, true, false], selection: $mood, label: { $0 == nil ? "All" : $0! ? "Light" : "Dark" }, hint: { _ in "Light or dark" })
                .frame(width: 140)
        }
        let filtering = !query.isEmpty || hue != nil || mood != nil
        if !filtering {
            if !favorites.isEmpty { section("★ Favourites", favorites, columns: 5) }
            if !recents.isEmpty { section("Recent", Array(recents.prefix(8)), columns: 8) }
        }
        let shown = Backdrop.allCases.filter { b in
            (query.isEmpty || b.name.localizedCaseInsensitiveContains(query) || b.group.rawValue.localizedCaseInsensitiveContains(query))
                && (hue == nil || b.hueFamily == hue) && (mood == nil || b.isLight == mood)
        }
        ForEach(Backdrop.Group.allCases) { g in
            let items = shown.filter { $0.group == g }
            if !items.isEmpty { section("\(g.rawValue) · \(items.count)", items, columns: 4) }
        }
        if shown.isEmpty { Text("Nothing matches. Try another colour.").font(.system(size: 12)).foregroundStyle(.secondary) }
    }

    private func section(_ title: String, _ items: [Backdrop], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(items) { b in tile(b) }
            }
        }
    }

    private func tile(_ b: Backdrop) -> some View {
        let on = s.style.fill == .backdrop && s.style.backdrop == b
        let fav = favorites.contains(b)
        return Button { pick(b) } label: {
            b.tile
                .aspectRatio(1.6, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.15)))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.mark : .clear, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    if fav { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color.mark).padding(5) }
                }
        }
        .buttonStyle(.plain)
        .help(b.name)
        .contextMenu {
            Button(fav ? "Remove from Favourites" : "Add to Favourites") {
                let list = fav ? favorites.filter { $0 != b } : favorites + [b]
                favoritesRaw = list.map(\.rawValue).joined(separator: ",")
            }
        }
    }

    private func pick(_ b: Backdrop) {
        s.style.fill = .backdrop
        s.style.backdrop = b
        recentsRaw = ([b] + recents.filter { $0 != b }).prefix(10).map(\.rawValue).joined(separator: ",")
    }

    @ViewBuilder private var magic: some View {
        Text("Built from your screenshot's colours").font(.system(size: 11.5)).foregroundStyle(.secondary)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Array(magicGradients(s.magicColors).enumerated()), id: \.offset) { _, g in
                let on = s.style.fill == .custom && s.style.gradient == g
                Button { s.style.fill = .custom; s.style.gradient = g } label: {
                    g.view.aspectRatio(1.6, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.mark : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        HStack(spacing: 5) {
            ForEach(s.magicColors, id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 14, height: 14) }
            Text("Colours found in the shot").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var gradient: some View {
        Chips(options: GradientKind.allCases, selection: Binding { s.style.gradient.kind } set: { s.style.gradient.kind = $0; s.style.fill = .custom },
              label: \.rawValue, hint: { "\($0.rawValue) gradient" })
        s.style.gradient.view.frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                ColorPicker("", selection: Binding {
                    Color(hex: s.style.gradient.colors[safe: i] ?? 0xFFFFFF)
                } set: { c in
                    var colors = s.style.gradient.colors
                    while colors.count < 3 { colors.append(colors.last ?? 0xFFFFFF) }
                    colors[i] = hexValue(c)
                    s.style.gradient.colors = colors
                    s.style.fill = .custom
                })
                .labelsHidden()
            }
            Spacer()
            Button("Shuffle", systemImage: "dice") {
                s.style.gradient = randomGradient(kind: s.style.gradient.kind)
                s.style.fill = .custom
            }
            .controlSize(.small)
            Button("From Shot") {
                s.style.gradient.colors = Array((s.magicColors + [0xFFFFFF, 0xFFFFFF, 0xFFFFFF]).prefix(3))
                s.style.fill = .custom
            }
            .controlSize(.small)
        }
        LabeledSlider(label: "Angle", value: Binding { CGFloat(s.style.gradient.angle) } set: { s.style.gradient.angle = Double($0.rounded()); s.style.fill = .custom },
                      range: 0...360, text: "\(Int(s.style.gradient.angle))°")
    }

    @ViewBuilder private var images: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            picture("Desktop", on: s.style.fill == .desktop) { s.style.fill = .desktop } image: {
                s.desktopImage.map { AnyView(Image(nsImage: $0).resizable().scaledToFill()) } ?? AnyView(Backdrop.boreal.view)
            }
            picture("Desktop glass", on: s.style.fill == .desktopGlass) { s.style.fill = .desktopGlass } image: {
                (s.desktopImage.map { AnyView(Image(nsImage: $0).resizable().scaledToFill()) } ?? AnyView(Backdrop.boreal.view)).blur(radius: 6)
            }
            picture("Your image", on: s.style.fill == .image) { act(.pickImage) } image: {
                if let p = s.style.imagePath, let i = Pictures.image(at: p) {
                    AnyView(Image(nsImage: i).resizable().scaledToFill())
                } else {
                    AnyView(Image(systemName: "photo.badge.plus").font(.system(size: 18)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.06)))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, let path = Pictures.keep(url) else { return false }
                s.style.imagePath = path
                s.style.fill = .image
                return true
            }
            ForEach(Backdrop.Group.wallpaper.backdrops + [.clear]) { b in
                picture(b.name, on: s.style.fill == .backdrop && s.style.backdrop == b) { pick(b) } image: { AnyView(b.tile) }
            }
        }
        Text("Drop a picture on Your image, or click it to choose one.").font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func picture(_ name: String, on: Bool, _ action: @escaping () -> Void, image: () -> some View) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                image()
                    .frame(height: 62)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(2)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.mark : .clear, lineWidth: 2))
                Text(name).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

enum HueFamily: String, CaseIterable, Identifiable {
    case red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", blue = "Blue", purple = "Purple", neutral = "Neutral"
    var id: Self { self }
    var swatch: Int {
        switch self {
        case .red: 0xF43F5E
        case .orange: 0xFB923C
        case .yellow: 0xFACC15
        case .green: 0x34D399
        case .blue: 0x3B82F6
        case .purple: 0xA855F7
        case .neutral: 0x9CA3AF
        }
    }
}

extension Backdrop {
    /// The colour family it reads as, for the colour filter.
    var hueFamily: HueFamily? {
        let hs = colors.map(hsl)
        guard !hs.isEmpty, group != .wallpaper else { return nil }
        if hs.map(\.s).reduce(0, +) / Double(hs.count) < 0.18 { return .neutral }
        let h = hs.max { $0.s < $1.s }!.h
        switch h {
        case ..<20, 335...: return .red
        case ..<45: return .orange
        case ..<70: return .yellow
        case ..<165: return .green
        case ..<250: return .blue
        default: return .purple
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

func hexValue(_ c: Color) -> Int {
    guard let n = NSColor(c).usingColorSpace(.sRGB) else { return 0 }
    return [n.redComponent, n.greenComponent, n.blueComponent].reduce(0) { $0 << 8 | Int((min(max($1, 0), 1) * 255).rounded()) }
}

// MARK: Small controls

private struct Group2<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
            content
        }
    }
}

/// Fine-tuning that appears while the pointer is over its row, as in ScreenSnap Pro.
private struct HoverReveal<Main: View, More: View>: View {
    @ViewBuilder let main: Main
    @ViewBuilder let more: More
    @State private var hovering = false

    init(@ViewBuilder _ main: () -> Main, @ViewBuilder more: () -> More) { self.main = main(); self.more = more() }

    var body: some View {
        VStack(spacing: 7) {
            main
            if hovering { more.transition(.opacity) }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Picture buttons with a caption, several to a row.
private struct Tiles<Option: Hashable, Icon: View>: View {
    let options: [Option]
    let columns: Int
    @Binding var selection: Option
    let label: (Option) -> String
    let icon: (Option) -> Icon

    init(_ options: [Option], columns: Int, selection: Binding<Option>, label: @escaping (Option) -> String, @ViewBuilder icon: @escaping (Option) -> Icon) {
        self.options = options; self.columns = columns; _selection = selection; self.label = label; self.icon = icon
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(options, id: \.self) { o in
                let on = selection == o
                Button { selection = o } label: {
                    VStack(spacing: 5) {
                        icon(o).frame(height: 24)
                        Text(label(o)).font(.system(size: 10.5)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(on ? .primary : .secondary)
                    .background(.white.opacity(on ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.mark : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SizeTile: View {
    let title: String
    let detail: String
    let ratio: CGFloat?
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                let r = ratio ?? 1.45, w: CGFloat = r >= 1 ? 22 : 22 * r, h: CGFloat = r >= 1 ? 22 / r : 22
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: ratio == nil ? [3, 2] : []))
                    .frame(width: w, height: max(h, 6))
                    .frame(height: 24)
                Text(title).font(.system(size: 10.5)).lineLimit(1).minimumScaleFactor(0.75)
                Text(detail).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(on ? .primary : .secondary)
            .background(.white.opacity(on ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.mark : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlacementGrid: View {
    @Binding var selection: Placement

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 3), count: 3), spacing: 3) {
            ForEach(Placement.allCases) { p in
                Button { selection = p } label: {
                    RoundedRectangle(cornerRadius: 4).fill(selection == p ? Color.mark : .white.opacity(0.14)).frame(width: 18, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .frame(width: 72)
    }
}

private struct NumberField: View {
    @Binding var value: CGFloat

    var body: some View {
        TextField("", value: Binding { Double(value) } set: { value = CGFloat($0) }, format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct FrameIcon: View {
    let frame: WindowFrame

    var body: some View {
        let bar: Color? = switch frame {
        case .mac, .safari: .white.opacity(0.8)
        case .macDark: Color(white: 0.25)
        case .chrome: Color(white: 0.7)
        case .windows: Color(white: 0.55)
        default: nil
        }
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: frame.isDevice ? 6 : 4)
                .fill(.white.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: frame.isDevice ? 6 : 4)
                    .strokeBorder(frame.isDevice ? Color(white: 0.05) : frame == .arc ? Color(hex: 0xC4B5FD) : .clear, lineWidth: 3))
            if let bar { bar.frame(height: 5) }
        }
        .frame(width: frame == .iphone ? 16 : 28, height: frame == .macbook ? 17 : 20)
        .clipShape(RoundedRectangle(cornerRadius: frame.isDevice ? 6 : 4))
        .opacity(frame == .none ? 0.5 : 1)
    }
}

/// A preset at thumbnail size: its background and a stand-in shot.
private struct PresetThumb: View {
    let style: Style

    var body: some View {
        ZStack {
            switch style.fill {
            case .custom: style.gradient.view
            default: style.backdrop.tile
            }
            VStack(spacing: 0) {
                if style.frame != .none { Color(white: 0.9).frame(height: 4) }
                Color.white
            }
            .frame(width: 52, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: style.shadowLook == .glow ? Color(hex: style.keyColor) : .black.opacity(style.shadowLook == .none ? 0 : 0.4),
                    radius: style.shadowLook == .hard ? 0 : 4, x: style.shadowLook == .hard ? 3 : 0, y: 3)
            .rotation3DEffect(.degrees(style.tilt.angles.y), axis: (0, 1, 0))
            .rotation3DEffect(.degrees(style.tilt.angles.x), axis: (1, 0, 0))
        }
        .clipped()
    }
}
