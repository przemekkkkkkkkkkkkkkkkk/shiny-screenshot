import SwiftUI

/// Full-screen, borderless, above everything. Non-activating, so the app you were in keeps focus afterwards.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

struct OverlayView: View {
    @Bindable var s: Session
    let act: (OverlayAction) -> Void

    var body: some View {
        let preview = s.style.enabled ? s.previewFrame : nil
        ZStack(alignment: .topLeading) {
            Image(decorative: s.image, scale: s.scale)
            Dim(hole: preview != nil ? nil : s.selection.isEmpty ? s.hoveredWindow : s.selection)
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { s.previewDragChanged(from: $0.startLocation, to: $0.location) }
                    .onEnded { s.previewDragEnded(from: $0.startLocation, to: $0.location) })
                .onContinuousHover { phase in
                    if case .active(let p) = phase, s.phase == .selecting { s.cursor = p }
                    (s.tool == .text ? NSCursor.iBeam : .crosshair).set()
                }
            if let w = s.hoveredWindow {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.mark, lineWidth: 2)
                    .frame(width: w.width, height: w.height)
                    .offset(x: w.minX, y: w.minY)
                    .allowsHitTesting(false)
            }
            if let preview {
                ComposedView(s: s)
                    .scaleEffect(preview.width / s.canvas.width, anchor: .topLeading)
                    .offset(x: preview.minX, y: preview.minY)
                    .allowsHitTesting(false)
                if s.phase == .editing {
                    // The shot stays resizable with the background on.
                    let (o, k) = s.onPreview(s.selection.origin)
                    let r = CGRect(origin: o, size: CGSize(width: s.selection.width * k, height: s.selection.height * k))
                    ForEach(Handle.allCases, id: \.self) { h in
                        let p = handlePoint(h, of: r)
                        HandleMark(handle: h)
                            .frame(width: 22, height: 22)
                            .offset(x: p.x - 11, y: p.y - 11)
                    }
                    .allowsHitTesting(false)
                }
            } else if !s.selection.isEmpty {
                ShotView(s: s)
                    .offset(x: s.selection.minX, y: s.selection.minY)
                    .allowsHitTesting(false)
                SelectionChrome(r: s.selection, scale: s.scale)
            }
            if let id = s.editingText, let a = s.annotations.first(where: { $0.id == id }) {
                // On the background preview the label is typed in place, at the preview's scale.
                let (o, k) = s.onPreview(a.labelFrame.origin)
                let h = a.labelFrame.height * k
                // A new identity per label, so each one takes the keyboard when it opens.
                TextDraft(s: s, a: a).id(id)
                    .scaleEffect(k, anchor: .topLeading)
                    .offset(x: o.x, y: o.y)
                LabelBar(s: s)
                    .offset(x: o.x, y: o.y > 56 ? o.y - 44 : o.y + h + 8)
            }
            if s.phase == .editing {
                Group {
                    if s.scrolling { ScrollStart(act: act) } else if s.recording { RecordStart(act: act) } else { Toolbar(s: s, act: act) }
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                .position(s.toolbarCenter(around: preview ?? s.selection))
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                if s.discardArmed {
                    Pill(text: "Press Esc again to discard your markup.", symbol: "exclamationmark.triangle.fill")
                        .position(x: s.size.width / 2, y: 70)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if s.tool == .text || s.editingText != nil {
                    Pill(text: s.editingText == nil ? "Click to add text. Click a label to edit it, drag to move it."
                                                    : "Return to finish, ⌥Return for a new line.", symbol: "character.cursor.ibeam")
                        .position(x: s.size.width / 2, y: 70)
                }
            }
            if preview != nil {
                // A docked toolbar takes the bottom 68 pt; the panel stays above it.
                let bottom: CGFloat = s.toolbarDocked ? 84 : 0
                StylePanel(s: s, act: act)
                    .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                    .position(x: s.size.width - s.panelRoom / 2, y: (s.size.height - bottom) / 2)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if s.phase == .selecting {
                Pill(text: s.windowsOnly ? "Click a window. Esc cancels."
                     : s.scrolling ? "Drag over the part that scrolls. Esc cancels."
                     : s.recording ? "Drag over the area to record, or click a window. Esc cancels."
                     : "Drag to select an area, or click a window. Esc cancels.", symbol: "viewfinder")
                    .position(x: s.size.width / 2, y: 70)
                if let c = s.cursor { Loupe(s: s, p: c) }
            }
        }
        .frame(width: s.size.width, height: s.size.height, alignment: .topLeading)
        // The toolbar springs in when the selection settles; pills and the panel fade and slide.
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: s.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: s.discardArmed)
        .ignoresSafeArea()
    }
}

private struct Dim: View {
    let hole: CGRect?

    var body: some View {
        Canvas { ctx, size in
            var path = Path(CGRect(origin: .zero, size: size))
            if let hole { path.addRect(hole) }
            ctx.fill(path, with: .color(.black.opacity(0.3)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}

private struct SelectionChrome: View {
    let r: CGRect
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.mark, lineWidth: 1.5)
                .frame(width: r.width, height: r.height)
                .shadow(color: Color.mark.opacity(0.6), radius: 5)
                .offset(x: r.minX, y: r.minY)
            ForEach(Handle.allCases, id: \.self) { h in
                let p = handlePoint(h, of: r)
                HandleMark(handle: h)
                    .frame(width: 22, height: 22)
                    .offset(x: p.x - 11, y: p.y - 11)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.mark).frame(width: 7, height: 7).glow(.mark)
                Text(verbatim: "\(Int((r.width * scale).rounded())) × \(Int((r.height * scale).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("px").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glassChrome(Capsule())
            .fixedSize()
            .offset(x: r.minX, y: max(r.minY - 36, 6))
        }
        .allowsHitTesting(false)
    }
}

/// Corner brackets and edge grips: the crop marks of the selection, drawn in Marker Yellow with a dark hairline so they
/// read on any screen.
private struct HandleMark: View {
    let handle: Handle

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), arm: CGFloat = 10
            var path = Path()
            switch handle {
            case .nw: path.addLines([CGPoint(x: c.x, y: c.y + arm), c, CGPoint(x: c.x + arm, y: c.y)])
            case .ne: path.addLines([CGPoint(x: c.x - arm, y: c.y), c, CGPoint(x: c.x, y: c.y + arm)])
            case .se: path.addLines([CGPoint(x: c.x, y: c.y - arm), c, CGPoint(x: c.x - arm, y: c.y)])
            case .sw: path.addLines([CGPoint(x: c.x + arm, y: c.y), c, CGPoint(x: c.x, y: c.y - arm)])
            case .n, .s: path.addLines([CGPoint(x: c.x - 8, y: c.y), CGPoint(x: c.x + 8, y: c.y)])
            case .e, .w: path.addLines([CGPoint(x: c.x, y: c.y - 8), CGPoint(x: c.x, y: c.y + 8)])
            }
            let round = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            ctx.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.mark), style: round)
        }
    }
}

/// The label being typed, styled like the finished one so nothing jumps on Return.
private struct TextDraft: View {
    @Bindable var s: Session
    let a: Annotation
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: a.cornerRadius)
        TextField("Type a note", text: $s.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Font(a.font as CTFont))
            .foregroundStyle(a.textColor)
            .shadow(color: .black.opacity(a.filled ? 0 : 0.75), radius: max(1.5, a.size / 10))
            .padding(.horizontal, a.inset.width)
            .padding(.vertical, a.inset.height)
            .frame(minWidth: s.draft.isEmpty ? a.size * 8 : 0, alignment: .leading)
            .fixedSize()
            .background(a.filled ? a.color : .clear, in: shape)
            // Plain text has no tag, so outline where the field is.
            .overlay(shape.strokeBorder(.white.opacity(a.filled ? 0 : 0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .focused($focused)
            .task { focused = true }
            // Picking a colour, size or look keeps typing in the label.
            .onChange(of: a.size) { focused = true }
            .onChange(of: a.filled) { focused = true }
            .onChange(of: a.color) { focused = true }
            .onSubmit { s.commitText() }
            .onExitCommand { s.commitText() }
    }
}

/// Look and size of the label being typed, floating just above it.
private struct LabelBar: View {
    @Bindable var s: Session

    var body: some View {
        let i = labelSizes.firstIndex(of: s.labelSize) ?? 1
        HStack(spacing: 2) {
            DockButton(symbol: "capsule.fill", on: s.labelFilled, help: "Text on a solid tag") { s.labelFilled = true }
            DockButton(symbol: "textformat", on: !s.labelFilled, help: "Plain text with an outline") { s.labelFilled = false }
            Divider().frame(height: 22).padding(.horizontal, 5)
            DockButton(symbol: "textformat.size.smaller", help: "Smaller") { s.labelSize = labelSizes[max(i - 1, 0)] }
                .disabled(i == 0)
            DockButton(symbol: "textformat.size.larger", help: "Larger") { s.labelSize = labelSizes[min(i + 1, labelSizes.count - 1)] }
                .disabled(i == labelSizes.count - 1)
            Divider().frame(height: 22).padding(.horizontal, 5)
            DockButton(symbol: "trash", help: "Delete label") {
                s.draft = ""
                s.commitText()
            }
        }
        .padding(5)
        .glassChrome(Capsule())
        .fixedSize()
    }
}

private struct Toolbar: View {
    @Bindable var s: Session
    let act: (OverlayAction) -> Void
    @State private var showColors = false
    @Namespace private var puck

    var body: some View {
        // One dock of glass islands (tools, colour, file, background) and the Copy button, blending as one surface.
        GlassGroup(spacing: 10) {
            HStack(spacing: 8) {
                island {
                    ForEach(Tool.allCases) { t in
                        DockButton(symbol: t.symbol, on: s.tool == t, puck: puck, help: "\(t.label)  \(t.key.uppercased())") {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { s.tool = s.tool == t ? nil : t }
                        }
                        .accessibilityLabel(t.label)
                    }
                }
                // One swatch at rest; it opens into the palette in place and closes on a pick.
                island {
                    ForEach(Array(zip(palette, paletteNames)), id: \.1) { c, name in
                        if showColors || s.color == c {
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    if showColors { s.color = c }
                                    showColors.toggle()
                                }
                            } label: {
                                ZStack {
                                    Circle().fill(c.gradient).frame(width: 22, height: 22)
                                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                                        .glow(c)
                                    if showColors && s.color == c {
                                        Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 30, height: 30)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(showColors ? name : "Colour: \(name)")
                            .accessibilityLabel(showColors ? name : "Colour, \(name)")
                            .accessibilityAddTraits(s.color == c ? .isSelected : [])
                        }
                    }
                }
                island {
                    DockButton(symbol: "arrow.uturn.backward", help: "Undo  ⌘Z") { s.undo() }
                    if s.video == nil { DockButton(symbol: "pin", help: "Pin above all windows") { act(.pin) } }
                    DockButton(symbol: "square.and.arrow.down", help: "Save to \(Shot.folderName)  ⌘S") { act(.save) }
                }
                island {
                    DockButton(symbol: "rectangle.on.rectangle.angled", title: s.compactToolbar ? nil : "Background",
                               on: s.style.enabled, toggle: true,
                               help: "Wrap the shot in a background") {
                        s.commitText()
                        s.pendingBackground = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { s.style.enabled.toggle() }
                    }
                }
                CopyButton(compact: s.compactToolbar) { act(.copy) }
            }
        }
        .fixedSize()
    }

    private func island(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 2) { content() }
            .padding(5)
            .glassChrome(Capsule())
    }
}

/// Screen recording's toolbar: sound and pointer, then start.
private struct RecordStart: View {
    let act: (OverlayAction) -> Void
    @AppStorage("recordSound") private var sound = false
    @AppStorage("recordCursor") private var cursor = true

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                DockButton(symbol: "xmark", help: "Cancel  Esc") { act(.cancel) }
                DockButton(symbol: sound ? "speaker.wave.2.fill" : "speaker.slash", on: sound, toggle: true,
                           help: sound ? "Records the Mac's sound" : "No sound") { sound.toggle() }
                DockButton(symbol: cursor ? "cursorarrow" : "cursorarrow.slash", on: cursor, toggle: true,
                           help: cursor ? "Shows the pointer" : "Hides the pointer") { cursor.toggle() }
            }
            .padding(5)
            .glassChrome(Capsule())
            PrimaryButton(title: "Start Recording", symbol: "record.circle", key: "↩") { act(.record) }
                .help("Start recording (Return)")
        }
        .fixedSize()
    }
}

/// Scrolling capture's toolbar: once the area is picked, start recording it.
private struct ScrollStart: View {
    let act: (OverlayAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack { DockButton(symbol: "xmark", help: "Cancel  Esc") { act(.cancel) } }
                .padding(5)
                .glassChrome(Capsule())
            PrimaryButton(title: "Start, then scroll", symbol: "arrow.down.to.line", key: "↩") { act(.scroll) }
                .help("Start recording (Return)")
        }
        .fixedSize()
    }
}

private struct CopyButton: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        PrimaryButton(title: "Copy", symbol: "doc.on.doc", key: compact ? nil : "↩", action: action)
            .help("Copy to clipboard (Return)")
    }
}

/// The one solid yellow action, with its glow and its key. Solid, because glass tints grey out in a non-key overlay.
private struct PrimaryButton: View {
    let title: String
    let symbol: String
    var key: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
                if let key {
                    Text(key)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .foregroundStyle(.black)
            .padding(.leading, 18)
            .padding(.trailing, key == nil ? 18 : 10)
            .frame(height: 50)
            .background(
                LinearGradient(colors: [Color(hex: 0xFFE14D), .mark, Color(hex: 0xF5C400)], startPoint: .top, endPoint: .bottom),
                in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1).blendMode(.overlay))
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glow(.mark)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = h } }
    }
}

/// A 40 pt dock control. Tools share one yellow puck that slides to the active tool; toggles light their glyph instead.
private struct DockButton: View {
    let symbol: String
    var title: String?
    var on = false
    var toggle = false
    var puck: Namespace.ID?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                if let title { Text(title).font(.system(size: 13.5, weight: .semibold)) }
            }
            .padding(.horizontal, title == nil ? 0 : 14)
            .frame(minWidth: 40, minHeight: 40)
            .foregroundStyle(on && !toggle ? .black : .primary)
            .background {
                if on && !toggle, let puck {
                    Capsule().fill(Color.mark.gradient).glow(.mark).matchedGeometryEffect(id: "puck", in: puck)
                } else if on && !toggle {
                    Capsule().fill(Color.mark.gradient).glow(.mark)
                } else if on {
                    // A lit switch: yellow wash and rim, text stays legible on any glass.
                    Capsule().fill(Color.mark.opacity(0.28)).overlay(Capsule().strokeBorder(Color.mark, lineWidth: 1.5))
                } else if hovering {
                    Capsule().fill(.primary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .accessibilityLabel(title ?? help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A native segmented control; the selected option's hint is its tooltip.
struct Segments<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let hint: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { o in Text(label(o)).tag(o) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help(hint(selection))
    }
}

extension View {
    /// Content visibly continues under the panel's bottom edge, where the platform draws that.
    @ViewBuilder
    func softBottomEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .bottom) } else { self }
    }
}

struct ColorRow: View {
    @Binding var selection: Int?

    var body: some View {
        HStack(spacing: 4) {
            swatch(nil) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 17)).foregroundStyle(.primary)
            }
            .help("Auto: dark or white to suit the background")
            ForEach(textColors, id: \.self) { hex in
                swatch(hex) { Circle().fill(Color(hex: hex)).overlay(Circle().strokeBorder(.primary.opacity(0.2))) }
            }
        }
    }

    private func swatch(_ hex: Int?, @ViewBuilder _ fill: () -> some View) -> some View {
        Button { selection = hex } label: {
            fill()
                .frame(width: 18, height: 18)
                .padding(2)
                .overlay(Circle().strokeBorder(selection == hex ? Color.mark : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct PanelField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
            .font(.system(size: 12.5))
    }
}

struct LabeledSlider: View {
    var symbol: String?
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 18)
            }
            Text(label).frame(width: 58, alignment: .leading)
            Slider(value: $value, in: range).tint(Color.mark).controlSize(.small)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .frame(minWidth: 34)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.07), in: Capsule())
        }
        .font(.system(size: 12.5))
    }
}

/// Magnified pixels under the cursor, with their coordinates.
private struct Loupe: View {
    let s: Session
    let p: CGPoint

    var body: some View {
        let px = CGPoint(x: (p.x * s.scale).rounded(.down), y: (p.y * s.scale).rounded(.down))
        let d: CGFloat = 120, zoom = d / 15
        // A 15×15 pixel window around the cursor. At screen edges only part of it exists; keep that part in place.
        let want = CGRect(x: px.x - 7, y: px.y - 7, width: 15, height: 15)
        let have = want.intersection(CGRect(x: 0, y: 0, width: s.image.width, height: s.image.height))
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.black
                if !have.isEmpty, let crop = s.image.cropping(to: have) {
                    Image(decorative: crop, scale: 1).interpolation(.none).resizable()
                        .frame(width: have.width * zoom, height: have.height * zoom)
                        .offset(x: (have.minX - want.minX) * zoom, y: (have.minY - want.minY) * zoom)
                }
            }
            .frame(width: d, height: d)
            .overlay {
                Rectangle().fill(.red.opacity(0.85)).frame(width: 1.5)
                Rectangle().fill(.red.opacity(0.85)).frame(height: 1.5)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            Text("\(Int(px.x)), \(Int(px.y))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
        }
        .position(x: min(p.x + 84, s.size.width - 70), y: min(p.y + 96, s.size.height - 84))
        .allowsHitTesting(false)
    }
}

private struct Pill: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.mark)
            Text(text).font(.system(size: 13.5, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .glassChrome(Capsule())
        .allowsHitTesting(false)
    }
}
