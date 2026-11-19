import SwiftUI

enum CardAction { case copy, save, pin, edit, library, dismiss }

/// Shown in the bottom-left corner after a capture. Hides itself after a few seconds unless hovered.
struct CardView: View {
    let title: String
    let image: NSImage
    @State var inLibrary = false
    let drag: () -> NSItemProvider
    let act: (CardAction) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            // The shot leads, edge to edge; status and dismiss float on it as glass.
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 284, height: 200)
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18)))
                .scaleEffect(hovering ? 1.01 : 1)
                .onDrag(drag)
                .help("Drag into any app")
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, Color.mark)
                        Text(title)
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .glassChrome(Capsule())
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    Button { act(.dismiss) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassChrome(Circle(), interactive: true)
                    .padding(8)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
            HStack(spacing: 6) {
                Button { act(.copy) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(LinearGradient(colors: [Color(hex: 0xFFE14D), .mark, Color(hex: 0xF5C400)],
                                                   startPoint: .top, endPoint: .bottom), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glow(.mark)
                CardButton(title: "Save", symbol: "square.and.arrow.down", iconOnly: true) { act(.save) }.help("Save")
                CardButton(title: "Pin", symbol: "pin", iconOnly: true) { act(.pin) }.help("Pin above all windows")
                CardButton(title: "Edit", symbol: "pencil", iconOnly: true) { act(.edit) }.help("Edit again")
                CardButton(title: "Library", symbol: inLibrary ? "checkmark" : "photo.stack", iconOnly: true) {
                    inLibrary = true
                    act(.library)
                }
                .disabled(inLibrary)
                .help(inLibrary ? "In the Library" : "Save to Library")
            }
            // The card window is sized for this row; glass buttons keep to it.
            .frame(height: 36)
        }
        .padding(8)
        .frame(width: 300)
        .glassChrome(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(20)
        .onHover { hovering = $0 }
        .task(id: hovering) {
            guard !hovering else { return }
            do {
                try await Task.sleep(for: .seconds(6))
                act(.dismiss)
            } catch {}
        }
    }
}

private struct CardButton: View {
    let title: String
    let symbol: String
    /// Same shape as its siblings, glyph only; the title stays for VoiceOver.
    var iconOnly = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(iconOnly ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: iconOnly ? 36 : nil, height: 36)
                .frame(maxWidth: iconOnly ? nil : .infinity)
                .background(.primary.opacity(hovering ? 0.08 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassChrome(Capsule(), interactive: true)
        .onHover { hovering = $0 }
    }
}

private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init(_ style: some LabelStyle) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// A capture floating above every window. Hover (or right-click) for opacity and close; drag anywhere to move.
struct PinView: View {
    let image: NSImage
    let size: CGSize
    let onClose: () -> Void
    let onOpacity: (Double) -> Void
    @State private var hovering = false
    @State private var opacity = 1.0

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                if hovering && size.width >= 80 {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill").font(.system(size: 11))
                        Slider(value: $opacity, in: 0.2...1).controlSize(.mini).frame(width: 110)
                        Spacer(minLength: 0)
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Close pin")
                    }
                    .padding(.horizontal, 10)
                    .frame(width: max(0, min(230, size.width - 16)), height: 30)
                    .glassChrome(Capsule())
                    .padding(8)
                            }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                Picker("Opacity", selection: $opacity) {
                    ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
                Button("Close Pin", action: onClose)
            }
            .onChange(of: opacity) { _, value in onOpacity(value) }
            .gesture(WindowDragGesture())
    }
}
