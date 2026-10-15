import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case arrow, rect, highlight, blur, step, text, pen

    var id: Self { self }

    var label: String {
        switch self {
        case .arrow: "Arrow"
        case .rect: "Rectangle"
        case .highlight: "Highlight"
        case .blur: "Blur"
        case .step: "Numbered step"
        case .text: "Text"
        case .pen: "Pen"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .highlight: "highlighter"
        case .blur: "checkerboard.rectangle"
        case .step: "1.circle"
        case .text: "textformat"
        case .pen: "scribble"
        }
    }

    var key: String {
        switch self {
        case .arrow: "a"
        case .rect: "r"
        case .highlight: "h"
        case .blur: "b"
        case .step: "n"
        case .text: "t"
        case .pen: "p"
        }
    }

    /// Steps and text are placed with a click; everything else is drawn by dragging.
    var placesOnClick: Bool { self == .step || self == .text }
}

struct Annotation: Identifiable {
    let id = UUID()
    var tool: Tool
    var color: Color
    /// Screen points. Two points for shapes, many for the pen, one for steps and text.
    var points: [CGPoint]
    var text = ""
    var number = 0

    var box: CGRect { rect(from: points[0], to: points[points.count - 1]) }
}

/// One capture, from selecting an area to the finished image. Coordinates are display points, top-left origin.
@Observable
final class Session {
    enum Phase { case selecting, editing }

    let image: CGImage
    let pixelated: CGImage
    let scale: CGFloat
    let size: CGSize
    let windows: [CGRect]
    let displayID: CGDirectDisplayID

    var phase = Phase.selecting
    /// Always on the device pixel grid, so the export is a pixel copy of the screen.
    var selection: CGRect {
        get { storedSelection }
        set { storedSelection = pixelAligned(newValue, scale: scale) }
    }
    private var storedSelection = CGRect.zero
    var annotations: [Annotation] = []
    var tool: Tool?
    var color = palette[0]
    var style = Style()
    var editingText: UUID?
    var draft = ""
    var cursor: CGPoint?

    /// `create` remembers what to restore if the new selection ends up too small.
    private enum Drag { case create(previous: CGRect, phase: Phase), move(CGRect), resize(Handle, CGRect), draw(UUID) }
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var dragStart: CGPoint?
    /// Furthest the pointer got from where the drag started; under 3 pt it counts as a click.
    @ObservationIgnored private var travelled: CGFloat = 0

    init(_ f: Capture.Frozen, displayID: CGDirectDisplayID) {
        image = f.image
        pixelated = f.pixelated
        scale = f.scale
        size = f.size
        windows = f.windows
        self.displayID = displayID
    }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    var screen: NSScreen? { NSScreen.screens.first { $0.displayID == displayID } }

    /// Before anything is selected, the window under the cursor is offered as the selection.
    var hoveredWindow: CGRect? {
        guard phase == .selecting, selection.isEmpty, let cursor else { return nil }
        return windows.first { $0.contains(cursor) }
    }

    func selectAll() {
        selection = bounds
        phase = .editing
    }

    func dragChanged(from a: CGPoint, to b: CGPoint) {
        if phase == .selecting { cursor = b }
        // A new start point means the previous gesture never ended (the overlay closed mid-drag).
        if dragStart != a {
            drag = nil
            dragStart = a
            travelled = 0
            commitText()
            drag = beginDrag(at: a)
        }
        travelled = max(travelled, a.distance(to: b))
        let d = CGSize(width: b.x - a.x, height: b.y - a.y)
        switch drag {
        case .create:
            if travelled > 3 { selection = rect(from: a, to: b).intersection(bounds) }
        case .move(let r):
            selection = moved(r, by: d, in: bounds)
        case .resize(let h, let r):
            selection = resized(r, handle: h, by: d, in: bounds)
        case .draw(let id):
            guard let i = annotations.firstIndex(where: { $0.id == id }) else { break }
            if annotations[i].tool == .pen { annotations[i].points.append(b) } else { annotations[i].points = [a, b] }
        case nil:
            break
        }
    }

    func dragEnded(from a: CGPoint, to b: CGPoint) {
        if dragStart != a { dragChanged(from: a, to: b) }
        let wasClick = travelled <= 3
        switch drag {
        case .draw(let id):
            // Shapes that end as a dot are dropped; a pen loop may end where it started.
            let pen = annotations.first { $0.id == id }?.tool == .pen
            if pen ? wasClick : a.distance(to: b) <= 3 { annotations.removeAll { $0.id == id } }
        case .create(let previous, let previousPhase):
            if selection.width >= minSelectionSide && selection.height >= minSelectionSide && !wasClick {
                if previousPhase == .editing { annotations = []; editingText = nil }
                phase = .editing
            } else {
                selection = previous
                phase = previousPhase
            }
        default:
            break
        }
        drag = nil
        dragStart = nil
        travelled = 0
        if wasClick { click(at: a) }
    }

    private func beginDrag(at p: CGPoint) -> Drag? {
        if phase == .selecting { return .create(previous: .zero, phase: .selecting) }
        if style.enabled { return nil }
        // Handle hit areas shrink with the selection so small selections can still be moved and drawn in.
        let reach = min(10, min(selection.width, selection.height) / 4)
        if let h = Handle.allCases.min(by: { handlePoint($0, of: selection).distance(to: p) < handlePoint($1, of: selection).distance(to: p) }),
           handlePoint(h, of: selection).distance(to: p) < reach {
            return .resize(h, selection)
        }
        guard selection.contains(p) else { return .create(previous: selection, phase: phase) }
        guard let tool else { return .move(selection) }
        if tool.placesOnClick { return nil }
        let a = Annotation(tool: tool, color: color, points: [p, p])
        annotations.append(a)
        return .draw(a.id)
    }

    private func click(at p: CGPoint) {
        if phase == .selecting {
            if let w = windows.first(where: { $0.contains(p) }) {
                selection = w.intersection(bounds)
                phase = .editing
            }
            return
        }
        guard !style.enabled, selection.contains(p), let tool, tool.placesOnClick else { return }
        var a = Annotation(tool: tool, color: color, points: [p])
        if tool == .step {
            a.number = annotations.filter { $0.tool == .step }.count + 1
        } else {
            draft = ""
            editingText = a.id
        }
        annotations.append(a)
    }

    func commitText() {
        guard let id = editingText else { return }
        editingText = nil
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            annotations.removeAll { $0.id == id }
        } else if let i = annotations.firstIndex(where: { $0.id == id }) {
            annotations[i].text = text
        }
    }

    func undo() {
        if annotations.popLast()?.id == editingText { editingText = nil }
    }

    /// Size of the exported image, in whole device pixels.
    var canvas: CGSize {
        let c = style.enabled ? canvasSize(shot: selection.size, padding: style.padding, ratio: style.ratio.value) : selection.size
        return CGSize(width: (c.width * scale).rounded() / scale, height: (c.height * scale).rounded() / scale)
    }

    /// Where the shot sits inside the canvas: centred, on the pixel grid.
    var shotOrigin: CGPoint {
        let c = canvas
        return CGPoint(x: ((c.width - selection.width) / 2 * scale).rounded() / scale,
                       y: ((c.height - selection.height) / 2 * scale).rounded() / scale)
    }

    func render() -> CGImage? {
        commitText()
        let renderer = ImageRenderer(content: ComposedView(s: self))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Where the background preview sits on screen: on the selection, scaled down to leave room for the panel.
    var previewFrame: CGRect {
        let c = canvas
        let k = max(0.05, min(1, (size.width - 340) / c.width, (size.height - 170) / c.height))
        let w = c.width * k, h = c.height * k
        return CGRect(x: min(max(selection.midX - w / 2, 20), size.width - 320 - w),
                      y: min(max(selection.midY - h / 2, 50), size.height - 100 - h),
                      width: w, height: h)
    }

    /// Below the target if there is room, else above it (clear of the notch), else inside its bottom edge.
    /// On screens too narrow to fit it beside the background panel, it docks at the bottom instead.
    func toolbarCenter(around r: CGRect) -> CGPoint {
        let half: CGFloat = 370
        if style.enabled && size.width - 300 < 2 * half {
            return CGPoint(x: max(size.width / 2, min(half, size.width - half)), y: size.height - 34)
        }
        let right = style.enabled ? size.width - 300 : size.width
        let top = screen?.safeAreaInsets.top ?? 0
        let y = r.maxY + 60 < size.height ? r.maxY + 34 : (r.minY - 60 > top ? r.minY - 34 : r.maxY - 34)
        return CGPoint(x: min(max(r.midX, half), right - half), y: y)
    }
}
