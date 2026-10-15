import CoreGraphics

nonisolated enum Handle: CaseIterable { case nw, n, ne, e, se, s, sw, w }

nonisolated func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}

nonisolated func moved(_ r: CGRect, by d: CGSize, in b: CGRect) -> CGRect {
    CGRect(x: min(max(r.minX + d.width, b.minX), b.maxX - r.width),
           y: min(max(r.minY + d.height, b.minY), b.maxY - r.height),
           width: r.width, height: r.height)
}

/// The smallest selection, in points, on either side.
nonisolated let minSelectionSide: CGFloat = 8

/// Drags one edge or corner, keeping the rect inside `b` and at least `m` points on each side.
/// A rect already under `m` grows inward, away from the screen edge.
nonisolated func resized(_ r: CGRect, handle h: Handle, by d: CGSize, in b: CGRect, minSide m: CGFloat = minSelectionSide) -> CGRect {
    var x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
    switch h {
    case .nw, .w, .sw:
        x0 = max(min(x0 + d.width, x1 - m), b.minX)
        x1 = max(x1, min(x0 + m, b.maxX))
    case .ne, .e, .se:
        x1 = min(max(x1 + d.width, x0 + m), b.maxX)
        x0 = min(x0, max(x1 - m, b.minX))
    case .n, .s: break
    }
    switch h {
    case .nw, .n, .ne:
        y0 = max(min(y0 + d.height, y1 - m), b.minY)
        y1 = max(y1, min(y0 + m, b.maxY))
    case .sw, .s, .se:
        y1 = min(max(y1 + d.height, y0 + m), b.maxY)
        y0 = min(y0, max(y1 - m, b.minY))
    case .e, .w: break
    }
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}

/// Snaps every edge to the device pixel grid, so exports copy pixels instead of resampling them.
nonisolated func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
    guard !r.isNull, !r.isInfinite else { return .zero }
    func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    let x0 = snap(r.minX), y0 = snap(r.minY)
    return CGRect(x: x0, y: y0, width: snap(r.maxX) - x0, height: snap(r.maxY) - y0)
}

nonisolated func handlePoint(_ h: Handle, of r: CGRect) -> CGPoint {
    switch h {
    case .nw: CGPoint(x: r.minX, y: r.minY)
    case .n: CGPoint(x: r.midX, y: r.minY)
    case .ne: CGPoint(x: r.maxX, y: r.minY)
    case .e: CGPoint(x: r.maxX, y: r.midY)
    case .se: CGPoint(x: r.maxX, y: r.maxY)
    case .s: CGPoint(x: r.midX, y: r.maxY)
    case .sw: CGPoint(x: r.minX, y: r.maxY)
    case .w: CGPoint(x: r.minX, y: r.midY)
    }
}

/// Size of the exported image: the shot plus padding, widened or heightened to match `ratio` (width / height).
nonisolated func canvasSize(shot: CGSize, padding p: CGFloat, ratio: CGFloat?) -> CGSize {
    var w = shot.width + 2 * p, h = shot.height + 2 * p
    if let ratio {
        if w / h < ratio { w = h * ratio } else { h = w / ratio }
    }
    return CGSize(width: w, height: h)
}

extension CGPoint {
    nonisolated func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
}
