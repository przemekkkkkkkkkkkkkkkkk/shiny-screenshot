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
                    .onChanged { s.dragChanged(from: $0.startLocation, to: $0.location) }
                    .onEnded { s.dragEnded(from: $0.startLocation, to: $0.location) })
                .onContinuousHover { phase in
                    if case .active(let p) = phase, s.phase == .selecting { s.cursor = p }
                    NSCursor.crosshair.set()
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
            } else if !s.selection.isEmpty {
                ShotView(s: s)
                    .offset(x: s.selection.minX, y: s.selection.minY)
                    .allowsHitTesting(false)
                SelectionChrome(r: s.selection, scale: s.scale)
            }
            if let id = s.editingText, let a = s.annotations.first(where: { $0.id == id }) {
                TextDraft(s: s, color: a.color)
                    .offset(x: a.points[0].x, y: a.points[0].y - 15)
            }
            if s.phase == .editing {
                Toolbar(s: s, act: act)
                    .position(s.toolbarCenter(around: preview ?? s.selection))
            }
            if preview != nil {
                BackgroundPanel(s: s)
                    .position(x: s.size.width - 150, y: s.size.height / 2)
            }
            if s.phase == .selecting {
                Pill(text: "Drag to select an area, or click a window. Esc cancels.")
                    .position(x: s.size.width / 2, y: 64)
                if let c = s.cursor { Loupe(s: s, p: c) }
            }
        }
        .frame(width: s.size.width, height: s.size.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

private struct Dim: View {
    let hole: CGRect?

    var body: some View {
        Canvas { ctx, size in
            var path = Path(CGRect(origin: .zero, size: size))
            if let hole { path.addRect(hole) }
            ctx.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
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
                .offset(x: r.minX, y: r.minY)
            ForEach(Handle.allCases, id: \.self) { h in
                let p = handlePoint(h, of: r)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.mark)
                    .frame(width: 10, height: 10)
                    .offset(x: p.x - 5, y: p.y - 5)
            }
            Text("\(Int((r.width * scale).rounded())) × \(Int((r.height * scale).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.mark, in: RoundedRectangle(cornerRadius: 5))
                .offset(x: r.minX, y: max(r.minY - 26, 4))
        }
        .allowsHitTesting(false)
    }
}

private struct TextDraft: View {
    @Bindable var s: Session
    let color: Color
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Type a note", text: $s.draft)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color == .mark ? .black : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minWidth: 140)
            .fixedSize()
            .background(color, in: RoundedRectangle(cornerRadius: 7))
            .focused($focused)
            .task { focused = true }
            .onSubmit { s.commitText() }
            .onExitCommand { s.commitText() }
    }
}

private struct Toolbar: View {
    @Bindable var s: Session
    let act: (OverlayAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { t in
                BarButton(symbol: t.symbol, on: s.tool == t, help: "\(t.label) (\(t.key.uppercased()))") {
                    s.tool = s.tool == t ? nil : t
                }
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            ForEach(palette, id: \.self) { c in
                Button { s.color = c } label: {
                    Circle().fill(c).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: s.color == c ? 2 : 0).padding(-3))
                        .frame(width: 24, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            BarButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { s.undo() }
            BarButton(symbol: "pin", help: "Pin to screen") { act(.pin) }
            BarButton(symbol: "square.and.arrow.down", help: "Save to \(Shot.folderName) (⌘S)") { act(.save) }
            BarButton(symbol: "photo.artframe", title: "Background", on: s.style.enabled, help: "Add a background") {
                s.commitText()
                s.style.enabled.toggle()
            }
            BarButton(symbol: "doc.on.doc", title: "Copy", on: true, help: "Copy to clipboard (Return)") { act(.copy) }
        }
        .padding(5)
        .background(Color(white: 0.11).opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

private struct BarButton: View {
    let symbol: String
    var title: String?
    var on = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                if let title { Text(title).font(.system(size: 12.5, weight: .semibold)) }
            }
            .padding(.horizontal, title == nil ? 0 : 10)
            .frame(minWidth: 30, minHeight: 30)
            .foregroundStyle(on ? .black : .white)
            .background(on ? Color.mark : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct BackgroundPanel: View {
    @Bindable var s: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Background").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Shuffle", systemImage: "shuffle") {
                    s.style.backdrop = Backdrop.allCases.filter { $0 != s.style.backdrop && $0 != .clear }.randomElement() ?? .peach
                }
                .controlSize(.small)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(Backdrop.allCases) { b in
                    Button { s.style.backdrop = b } label: {
                        b.tile
                            .frame(height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.15)))
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(s.style.backdrop == b ? Color.mark : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(b.name)
                }
            }
            // The selection ring sits in each tile's padding; pull the grid out so the swatches line up with the rest.
            .padding(.horizontal, -3)
            Divider()
            LabeledSlider(label: "Padding", value: $s.style.padding, range: 0...160, text: "\(Int(s.style.padding))")
            LabeledSlider(label: "Roundness", value: $s.style.radius, range: 0...32, text: "\(Int(s.style.radius))")
            LabeledSlider(label: "Shadow", value: $s.style.shadow, range: 0...0.8, text: "\(Int(s.style.shadow * 125))%")
            Divider()
            VStack(alignment: .leading, spacing: 6) {
              Text("Size").font(.system(size: 12)).foregroundStyle(.secondary)
              HStack(spacing: 4) {
                ForEach(Ratio.allCases) { r in
                    let on = s.style.ratio == r
                    Button { s.style.ratio = r } label: {
                        Text(r.rawValue)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(on ? .black : .primary)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(on ? Color.mark : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(r.hint)
                }
              }
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(Color(white: 0.11).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let text: String

    var body: some View {
        HStack {
            Text(label).frame(width: 74, alignment: .leading).foregroundStyle(.secondary)
            Slider(value: $value, in: range).tint(Color.mark)
            Text(text).monospacedDigit().frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 12))
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

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(white: 0.11).opacity(0.9), in: Capsule())
            .allowsHitTesting(false)
    }
}
