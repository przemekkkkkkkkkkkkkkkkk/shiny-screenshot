import SwiftUI

/// Stitches frames of one scrolling area into a single tall image, matching rows between frames to find how far it scrolled.
nonisolated enum Stitch {
    /// The overlay scroll bar comes and goes while scrolling, so the right edge is left out of row matching.
    static let scrollBarWidth: CGFloat = 24
    /// Tallest result, in pixels.
    static let maxHeight = 40_000

    /// One hash per pixel row, top to bottom, ignoring the rightmost `ignoringRight` pixels.
    static func rows(_ image: CGImage, ignoringRight: Int) -> [Int] {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = UnsafeRawBufferPointer(start: data, count: w * h * 4)
        let used = max(1, w - ignoringRight) * 4
        return (0..<h).map { y in
            var hasher = Hasher()
            hasher.combine(bytes: UnsafeRawBufferPointer(rebasing: bytes[(y * w * 4)..<(y * w * 4 + used)]))
            return hasher.finalize()
        }
    }

    /// How many rows the content moved up from `old` to `new`, or nil if it didn't scroll down or the frames don't overlap.
    /// Each row seen in both frames votes for its shift. Rows that repeat (blank space, rules) say nothing, and rows that
    /// stayed put (a sticky header) vote for 0, so a shift has to beat them.
    static func offset(from old: [Int], to new: [Int]) -> Int? {
        var at: [Int: [Int]] = [:]
        for (j, hash) in old.enumerated() { at[hash, default: []].append(j) }
        var votes = [Int](repeating: 0, count: old.count)
        for (i, hash) in new.enumerated() {
            guard let js = at[hash], js.count <= 3 else { continue }
            for j in js where j >= i { votes[j - i] += 1 }
        }
        guard let best = votes.indices.dropFirst().max(by: { votes[$0] < votes[$1] }),
              votes[best] >= 8, votes[best] > votes[0] else { return nil }
        return best
    }

    /// Rows `from..<image.height` copied out, so the strip doesn't keep the whole frame alive.
    static func strip(_ image: CGImage, from y: Int) -> CGImage? {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: image.height - y)).flatMap(copy)
    }

    static func copy(_ image: CGImage) -> CGImage? {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx?.makeImage()
    }

    /// The strips stacked top to bottom.
    static func compose(_ strips: [CGImage]) -> CGImage? {
        guard let w = strips.first?.width else { return nil }
        let h = strips.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var top = 0
        for s in strips {
            top += s.height
            ctx.draw(s, in: CGRect(x: 0, y: h - top, width: s.width, height: s.height))
        }
        return ctx.makeImage()
    }
}

/// Captures one area of the screen over and over while you scroll it, adding what scrolls into view.
/// ponytail: downward scrolling only, and sticky footers repeat in the result; handle them if people scroll up or hit footers.
@Observable
final class Scrolling {
    let area: CGRect
    let displayID: CGDirectDisplayID
    let scale: CGFloat
    /// Height captured so far, in pixels.
    private(set) var height = 0
    /// The last frames didn't line up with the result: scrolled too fast, or back up.
    private(set) var lost = false
    @ObservationIgnored private var strips: [CGImage] = []
    @ObservationIgnored private var last: [Int]?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(area: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) {
        self.area = area
        self.displayID = displayID
        self.scale = scale
    }

    func start() {
        task = Task {
            while !Task.isCancelled {
                if let frame = try? await Capture.area(area, displayID: displayID, scale: scale) { await add(frame) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Stops and returns everything captured.
    func finish() async -> CGImage? {
        task?.cancel()
        await task?.value
        let strips = strips
        return await Task.detached { Stitch.compose(strips) }.value
    }

    func cancel() { task?.cancel() }

    private func add(_ frame: CGImage) async {
        let ignore = Int(Stitch.scrollBarWidth * scale)
        let rows = await Task.detached { Stitch.rows(frame, ignoringRight: ignore) }.value
        guard let last else {
            if let first = await Task.detached(operation: { Stitch.copy(frame) }).value {
                strips = [first]
                height = first.height
                self.last = rows
            }
            return
        }
        guard rows.count == last.count, height < Stitch.maxHeight else { return }
        guard let dy = Stitch.offset(from: last, to: rows) else {
            // Unchanged frames are fine; a changed frame that doesn't line up means it scrolled too far, or up.
            lost = rows != last
            return
        }
        guard let strip = await Task.detached(operation: { Stitch.strip(frame, from: frame.height - dy) }).value else { return }
        strips.append(strip)
        height += dy
        lost = false
        self.last = rows
    }
}

/// Floats under the area while it records: how much is captured, and Done or Cancel.
struct ScrollingBar: View {
    let s: Scrolling
    let done: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(s.lost ? "Lost track: scroll back, slower" : "Scroll down · \(s.height) px")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(s.lost ? Color.mark : .white)
                .frame(minWidth: 170, alignment: .leading)
            Button("Cancel", action: cancel).controlSize(.small)
            Button("Done", action: done).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.11).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(8)
    }
}

/// Counts down before a delayed capture. Click it to cancel.
struct CountdownView: View {
    let seconds: Int
    /// True when the countdown ran out, false when cancelled.
    let finish: (Bool) -> Void
    @State private var left = 0

    var body: some View {
        Button { finish(false) } label: {
            VStack(spacing: 2) {
                Text("\(left)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Click to cancel").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(width: 110, height: 86)
            .background(Color(white: 0.11).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .padding(20)
        .task {
            left = seconds
            while left > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                left -= 1
            }
            finish(true)
        }
    }
}
