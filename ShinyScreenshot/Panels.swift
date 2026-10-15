import SwiftUI

enum CardAction { case copy, save, pin, edit, dismiss }

/// Shown in the bottom-left corner after a capture. Hides itself after a few seconds unless hovered.
struct CardView: View {
    let title: String
    let image: NSImage
    let drag: () -> NSItemProvider
    let act: (CardAction) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button { act(.dismiss) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 276, height: 166)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .onDrag(drag)
                .help("Drag into any app")
            HStack(spacing: 6) {
                CardButton(title: "Copy", symbol: "doc.on.doc") { act(.copy) }
                CardButton(title: "Save", symbol: "square.and.arrow.down") { act(.save) }
                CardButton(title: "Pin", symbol: "pin") { act(.pin) }
                CardButton(title: "Edit", symbol: "pencil") { act(.edit) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Color(white: 0.12).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(20)
        .environment(\.colorScheme, .dark)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
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
                    .frame(width: max(0, min(230, size.width - 16)), height: 28)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(8)
                    .environment(\.colorScheme, .dark)
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
