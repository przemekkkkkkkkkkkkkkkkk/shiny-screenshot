import SwiftUI
import Vision

enum Tool: String, CaseIterable, Identifiable, Codable {
    case arrow, rect, highlight, spotlight, blur, step, text, pen

    var id: Self { self }

    var label: String {
        switch self {
        case .arrow: "Arrow"
        case .rect: "Rectangle"
        case .highlight: "Highlight"
        case .spotlight: "Spotlight"
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
        case .spotlight: "flashlight.on.fill"
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
        case .spotlight: "s"
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
    /// Text labels only: point size, and a solid tag or outlined text.
    var size: CGFloat = 15
    var filled = true

    var box: CGRect { rect(from: points[0], to: points[points.count - 1]) }
}

/// One capture, from selecting an area to the finished image. Coordinates are display points, top-left origin.
@Observable
final class Session {
    enum Phase { case selecting, editing }

    let image: CGImage
    /// Same screen, pixelated, for the blur tool. Made in the background while the overlay is open, dropped when it closes.
    private(set) var pixelated: CGImage?
    @ObservationIgnored private var pixelating: Task<Void, Never>?
    @ObservationIgnored private let noiseSeed = Capture.randomSeed()
    let scale: CGFloat
    let size: CGSize
    let windows: [Capture.Window]
    let displayID: CGDirectDisplayID

    var phase = Phase.selecting
    /// Always on the device pixel grid, so the export is a pixel copy of the screen.
    var selection: CGRect {
        get { storedSelection }
        set { storedSelection = pixelAligned(newValue, scale: scale) }
    }
    private var storedSelection = CGRect.zero
    var annotations: [Annotation] = []
    var tool: Tool? { didSet { if tool != nil { applyPendingBackground() } } }
    /// The Settings background, waiting for the area to be settled: it turns on with the first tool or the export.
    var pendingBackground = false
    /// Colour, label size and look apply to the next annotation and to the label being typed.
    var color = palette[0] { didSet { editLabel { $0.color = color } } }
    var labelSize: CGFloat = 15 { didSet { editLabel { $0.size = labelSize } } }
    var labelFilled = true { didSet { editLabel { $0.filled = labelFilled } } }
    var style = Style()
    /// The background panel's open section.
    var panelSection = StylePanel.Section.fill
    var fillTab = FillTab.library
    var editingText: UUID?
    var draft = ""
    var cursor: CGPoint?
    /// The clicked window captured on its own; arrives a moment after the click.
    var windowShot: Capture.WindowShot?
    /// Window capture: dragging selects nothing, only clicking a window does.
    var windowsOnly = false
    /// Scrolling capture: the selection is the area to record, not to mark up.
    var scrolling = false
    /// How the capture started and the app in front then, for the Library.
    var mode = CaptureMode.area
    var app: String?
    /// The Library entry this capture is, or becomes: reopening one and copying again updates it.
    var shotID = UUID()
    /// Pixels per point the export is tagged with, when it differs from `scale`: a capture shrunk to fit a smaller
    /// screen keeps every pixel and pastes at its original size.
    var pasteScale: CGFloat?
    /// A screen recording this session styles; the frozen image is its first frame.
    var video: URL?
    /// Recording: the selection is the area to record, not to mark up.
    var recording = false
    /// Emails, keys and the like found in the selection, in screen points; hidden when the style asks.
    private(set) var redactions: [CGRect] = []
    @ObservationIgnored private var redactedSelection: CGRect?
    @ObservationIgnored private var magicCache: (CGRect, [Int])?
    @ObservationIgnored private var balanceCache: (CGRect, CGRect)?

    /// `create` remembers what to restore if the new selection ends up too small.
    private enum Drag {
        case create(previous: CGRect, phase: Phase), move(CGRect), resize(Handle, CGRect), draw(UUID), moveLabel(UUID, CGPoint)
    }
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var dragStart: CGPoint?
    /// Furthest the pointer got from where the drag started; under 3 pt it counts as a click.
    @ObservationIgnored private var travelled: CGFloat = 0

    init(_ f: Capture.Frozen, displayID: CGDirectDisplayID) {
        image = f.image
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
        return windows.first { $0.frame.contains(cursor) }?.frame.intersection(bounds)
    }

    /// The window shot, while the selection is still the window it was taken for.
    var activeWindowShot: Capture.WindowShot? {
        windowShot.flatMap { $0.selection == selection ? $0 : nil }
    }

    func applyPendingBackground() {
        guard pendingBackground else { return }
        pendingBackground = false
        style.enabled = true
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
        case .moveLabel(let id, let origin):
            guard let i = annotations.firstIndex(where: { $0.id == id }) else { break }
            annotations[i].points = [CGPoint(x: origin.x + d.width, y: origin.y + d.height)]
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
        case .moveLabel(let id, let origin) where wasClick:
            // A click edits the label; undo the jitter of the press.
            if let i = annotations.firstIndex(where: { $0.id == id }) { annotations[i].points = [origin] }
        default:
            break
        }
        drag = nil
        dragStart = nil
        travelled = 0
        if wasClick { click(at: a) }
    }

    private func beginDrag(at p: CGPoint) -> Drag? {
        if phase == .selecting { return windowsOnly ? nil : .create(previous: .zero, phase: .selecting) }
        // With a background on, the preview is for drawing only: no handles, no moving or reselecting.
        if style.enabled {
            guard selection.contains(p) else { return nil }
        } else {
            // Handle hit areas shrink with the selection so small selections can still be moved and drawn in.
            let reach = min(10, min(selection.width, selection.height) / 4)
            if let h = Handle.allCases.min(by: { handlePoint($0, of: selection).distance(to: p) < handlePoint($1, of: selection).distance(to: p) }),
               handlePoint(h, of: selection).distance(to: p) < reach {
                return .resize(h, selection)
            }
            guard selection.contains(p) else { return .create(previous: selection, phase: phase) }
        }
        if let l = label(at: p) { return .moveLabel(l.id, l.points[0]) }
        guard let tool else { return style.enabled ? nil : .move(selection) }
        if tool.placesOnClick { return nil }
        let a = Annotation(tool: tool, color: color, points: [p, p])
        annotations.append(a)
        return .draw(a.id)
    }

    private func click(at p: CGPoint) {
        if phase == .selecting {
            if let w = windows.first(where: { $0.frame.contains(p) }) {
                selection = w.frame.intersection(bounds)
                phase = .editing
                captureWindow(w)
            }
            return
        }
        guard selection.contains(p) else { return }
        if let l = label(at: p) { return edit(l) }
        guard let tool, tool.placesOnClick else { return }
        var a = Annotation(tool: tool, color: color, points: [p], size: labelSize, filled: labelFilled)
        if tool == .step {
            a.number = annotations.filter { $0.tool == .step }.count + 1
        } else {
            draft = ""
            editingText = a.id
        }
        annotations.append(a)
    }

    private func captureWindow(_ w: Capture.Window) {
        guard w.id != kCGNullWindowID, !scrolling else { return }
        let (selection, scale) = (selection, scale)
        Task { if let shot = try? await Capture.window(w, for: selection, scale: scale) { windowShot = shot } }
    }

    /// The topmost text label under `p`, when no tool or the text tool is picked; other tools draw over labels.
    private func label(at p: CGPoint) -> Annotation? {
        guard tool == nil || tool == .text else { return nil }
        return annotations.last { $0.tool == .text && $0.labelFrame.contains(p) }
    }

    private func edit(_ a: Annotation) {
        color = a.color
        labelSize = a.size
        labelFilled = a.filled
        draft = a.text
        editingText = a.id
    }

    private func editLabel(_ change: (inout Annotation) -> Void) {
        guard let id = editingText, let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        change(&annotations[i])
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

    /// Esc with markup on screen asks twice, so one Esc too many doesn't throw the work away.
    var discardArmed = false
    @ObservationIgnored private var disarming: Task<Void, Never>?

    func armDiscard() {
        discardArmed = true
        disarming?.cancel()
        disarming = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            discardArmed = false
        }
    }

    func undo() {
        if annotations.popLast()?.id == editingText { editingText = nil }
    }

    /// The part of the screen that is exported: the selection, or with auto balance, the selection trimmed so the
    /// plain margin around its content is the same on every side (after CleanShot X).
    var shotArea: CGRect {
        guard style.enabled, style.autoBalance else { return selection }
        if let (r, a) = balanceCache, r == selection { return a }
        let px = CGRect(x: selection.minX * scale, y: selection.minY * scale, width: selection.width * scale, height: selection.height * scale)
        var area = selection
        if let crop = image.cropping(to: px.integral), let m = plainMargins(crop) {
            let even = min(m.top, m.left, m.bottom, m.right)
            area = pixelAligned(CGRect(x: selection.minX + CGFloat(m.left - even) / scale, y: selection.minY + CGFloat(m.top - even) / scale,
                                       width: selection.width - CGFloat(m.left + m.right - 2 * even) / scale,
                                       height: selection.height - CGFloat(m.top + m.bottom - 2 * even) / scale), scale: scale)
        }
        balanceCache = (selection, area)
        return area
    }

    /// The shot with its window frame and ring, before padding.
    var boxSize: CGSize {
        let a = shotArea.size
        guard style.enabled else { return a }
        let c = style.frame.chrome, ring = style.ringWidth
        return CGSize(width: a.width + c.left + c.right + 2 * ring, height: a.height + c.top + c.bottom + 2 * ring)
    }

    /// Title and description, when the background is on and there is text to show.
    var heading: HeadingLayout? {
        style.enabled ? HeadingLayout(style, width: max(boxSize.width, 320)) : nil
    }

    /// Every copy of the shot together: one, two side by side, or a stack.
    private var groupSize: CGSize {
        let b = boxSize
        switch style.enabled ? style.layout : .single {
        case .single: return b
        case .duo: return CGSize(width: b.width * 1.61, height: b.height * 1.07)
        case .stack: return CGSize(width: b.width * 1.1, height: b.height * 1.1)
        }
    }

    /// The shots plus their title and description, before padding.
    private var content: CGSize {
        let g = groupSize
        guard let h = heading else { return g }
        return CGSize(width: max(g.width, h.width), height: g.height + h.gap + h.height)
    }

    var effectivePadding: CGFloat { style.padding }

    /// How far the shot runs off the canvas edge, when it bleeds.
    private var bleedDepth: CGFloat {
        style.enabled && style.bleed && !style.autoBalance ? (boxSize.height * 0.18).rounded() : 0
    }

    /// Size of the exported image, in whole device pixels.
    var canvas: CGSize {
        guard style.enabled else { return snappedSize(shotArea.size) }
        let p = effectivePadding, bleed = bleedDepth
        var c = canvasSize(shot: content, padding: p, ratio: nil)
        if bleed > 0 { c.height -= p + bleed }
        if let r = style.aspect {
            if c.width / c.height < r { c.width = c.height * r } else { c.height = c.width / r }
        }
        return snappedSize(c)
    }

    private func snappedSize(_ c: CGSize) -> CGSize {
        CGSize(width: (c.width * scale).rounded() / scale, height: (c.height * scale).rounded() / scale)
    }

    private var contentOrigin: CGPoint {
        let c = canvas, inner = content, p = effectivePadding, bleed = bleedDepth
        let unit = style.autoBalance ? CGPoint(x: 0.5, y: 0.5) : style.placement.unit
        let x = p + (c.width - inner.width - 2 * p) * unit.x
        if bleed > 0 { return CGPoint(x: x, y: unit.y == 0 ? -bleed : c.height - inner.height + bleed) }
        return CGPoint(x: x, y: p + (c.height - inner.height - 2 * p) * unit.y)
    }

    /// Where the group of shots starts.
    private var groupOrigin: CGPoint {
        let o = contentOrigin, g = groupSize
        let dx = (content.width - g.width) / 2
        let dy = heading.map { $0.style.below ? 0 : $0.height + $0.gap } ?? 0
        return CGPoint(x: o.x + dx, y: o.y + dy)
    }

    /// Where the shot itself (the selection) sits inside the canvas, on the pixel grid.
    var shotOrigin: CGPoint {
        guard style.enabled else { return .zero }
        let g = groupOrigin, b = boxSize, gs = groupSize
        let box = style.layout == .stack ? CGPoint(x: g.x + gs.width - b.width, y: g.y + gs.height - b.height) : g
        let c = style.frame.chrome, ring = style.ringWidth
        return snapped(CGPoint(x: box.x + c.left + ring, y: box.y + c.top + ring))
    }

    /// The framed shot: frame and ring around the selection.
    var boxFrame: CGRect {
        let o = shotOrigin, c = (style.enabled ? style.frame : .none).chrome, ring = style.enabled ? style.ringWidth : 0
        return CGRect(origin: CGPoint(x: o.x - c.left - ring, y: o.y - c.top - ring), size: boxSize)
    }

    var textOrigin: CGPoint {
        guard let h = heading else { return .zero }
        let o = contentOrigin
        let x = o.x + (content.width - h.width) / 2
        return snapped(CGPoint(x: x, y: h.style.below ? o.y + groupSize.height + h.gap : o.y))
    }

    private func snapped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x * scale).rounded() / scale, y: (p.y * scale).rounded() / scale)
    }

    /// Pixels per point of the export.
    var exportScale: CGFloat {
        style.enabled ? style.size.scale(screen: scale, width: canvas.width) : scale
    }

    /// Colours that stand out in the selection, for the Magic backgrounds.
    var magicColors: [Int] {
        if let (r, c) = magicCache, r == selection { return c }
        let px = CGRect(x: selection.minX * scale, y: selection.minY * scale, width: selection.width * scale, height: selection.height * scale)
        let c = image.cropping(to: px.integral).map { dominantColors($0) } ?? []
        magicCache = (selection, c)
        return c
    }

    /// Finds emails, keys and the like in the selection, once per selection.
    func detectSensitive() {
        guard style.enabled, style.redact else { return }
        guard redactedSelection != selection else { return }
        redactedSelection = selection
        let sel = selection
        let px = CGRect(x: sel.minX * scale, y: sel.minY * scale, width: sel.width * scale, height: sel.height * scale)
        guard let crop = image.cropping(to: px.integral) else { return redactions = [] }
        redactions = Self.sensitiveBoxes(in: crop).map {
            CGRect(x: sel.minX + $0.minX * sel.width, y: sel.minY + $0.minY * sel.height, width: $0.width * sel.width, height: $0.height * sel.height)
                .insetBy(dx: -3, dy: -3)
        }
        if !redactions.isEmpty { pixelatedNow() }
    }

    /// Boxes, as fractions of the image with a top-left origin, around text that looks sensitive.
    nonisolated static func sensitiveBoxes(in image: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).flatMap { o -> [CGRect] in
            guard let c = o.topCandidates(1).first else { return [] }
            return sensitiveRanges(in: c.string).compactMap { r in
                (try? c.boundingBox(for: r)).map { b in
                    let r = b.boundingBox
                    return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
                }
            }
        }
    }

    /// The wallpaper behind this screen, for the Desktop backgrounds.
    var desktopImage: NSImage? { Pictures.desktop(for: screen) }

    /// What the export hides: redactions while they're on.
    var hiddenAreas: [CGRect] { style.enabled && style.redact ? redactions : [] }

    func preparePixelated() {
        guard pixelated == nil, pixelating == nil else { return }
        let (image, scale, seed) = (image, scale, noiseSeed)
        pixelating = Task {
            let p = await Task.detached { Capture.pixelate(image, scale: scale, seed: seed) ?? Capture.grey }.value
            guard !Task.isCancelled else { return }
            pixelated = p
            pixelating = nil
        }
    }

    /// Frees the blur copy: a closed session (kept for Edit) only needs the screen itself.
    func releasePixelated() {
        pixelating?.cancel()
        pixelating = nil
        pixelated = nil
    }

    /// The blur copy, made on the spot if the background one isn't ready.
    @discardableResult
    func pixelatedNow() -> CGImage {
        if let pixelated { return pixelated }
        releasePixelated()
        let p = Capture.pixelate(image, scale: scale, seed: noiseSeed) ?? Capture.grey
        pixelated = p
        return p
    }

    /// Nothing see-through: no transparent background and no window corners. Saved as RGB, which is smaller.
    var isOpaque: Bool {
        guard style.enabled else { return activeWindowShot == nil }
        return !(style.fill == .backdrop && style.backdrop == .clear) && !style.transparent && style.canvasRadius == 0
    }

    func render() -> CGImage? {
        commitText()
        // Blur must never fall back to grey in the export.
        if activeWindowShot == nil, annotations.contains(where: { $0.tool == .blur }) { pixelatedNow() }
        detectSensitive()
        let renderer = ImageRenderer(content: ComposedView(s: self))
        renderer.scale = exportScale
        return renderer.cgImage
    }

    /// Width kept clear on the right for the style panel, its margin included.
    let panelRoom: CGFloat = 450

    /// Screen point on the background preview -> the same spot on the frozen screen, where annotations live.
    func fromPreview(_ p: CGPoint) -> CGPoint {
        guard style.enabled, phase == .editing else { return p }
        let f = previewFrame, k = f.width / canvas.width, o = shotOrigin
        return CGPoint(x: shotArea.minX + (p.x - f.minX) / k - o.x, y: shotArea.minY + (p.y - f.minY) / k - o.y)
    }

    /// The inverse of `fromPreview`, and the preview's scale: where a label being typed shows, and how big.
    func onPreview(_ q: CGPoint) -> (point: CGPoint, scale: CGFloat) {
        guard style.enabled else { return (q, 1) }
        let f = previewFrame, k = f.width / canvas.width, o = shotOrigin
        return (CGPoint(x: f.minX + (q.x - shotArea.minX + o.x) * k, y: f.minY + (q.y - shotArea.minY + o.y) * k), k)
    }

    /// Screens too narrow for the toolbar beside the background panel: it docks at the bottom, under a shorter panel.
    var toolbarDocked: Bool { style.enabled && size.width - panelRoom < 2 * toolbarHalfWidth }
    /// Narrow screens get the compact toolbar: Background and Copy lose their labels.
    var compactToolbar: Bool { size.width < 900 }
    /// Half the toolbar's measured width, glow and shadow included.
    var toolbarHalfWidth: CGFloat { compactToolbar ? 360 : 432 }

    /// Where the background preview sits on screen: on the selection, scaled down to leave room for the panel.
    var previewFrame: CGRect {
        let c = canvas
        let k = max(0.05, min(1, (size.width - panelRoom - 40) / c.width, (size.height - 170) / c.height))
        let w = c.width * k, h = c.height * k
        return CGRect(x: min(max(selection.midX - w / 2, 20), size.width - panelRoom - 20 - w),
                      y: min(max(selection.midY - h / 2, 50), size.height - 100 - h),
                      width: w, height: h)
    }

    /// Below the target if there is room, else above it (clear of the notch), else inside its bottom edge.
    /// On screens too narrow to fit it beside the background panel, it docks at the bottom instead.
    func toolbarCenter(around r: CGRect) -> CGPoint {
        let half = toolbarHalfWidth
        if toolbarDocked {
            return CGPoint(x: max(size.width / 2, min(half, size.width - half)), y: size.height - 42)
        }
        let right = style.enabled ? size.width - panelRoom : size.width
        let top = screen?.safeAreaInsets.top ?? 0
        let y = r.maxY + 76 < size.height ? r.maxY + 42 : (r.minY - 76 > top ? r.minY - 42 : r.maxY - 42)
        return CGPoint(x: min(max(r.midX, half), right - half), y: y)
    }
}
