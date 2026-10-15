import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import ShinyScreenshot

/// Session.render() and Shot: pixel sizes, pixel accuracy, blur alignment, PNG/TIFF payloads, saving, and huge canvases.
struct ExportTests {
    static let coded1x = Fixture.coded(1440, 900)
    static let coded2x = Fixture.coded(2880, 1800)

    func session(scale: CGFloat, selection: CGRect) -> Session {
        let s = Fixture.session(scale == 1 ? Self.coded1x : Self.coded2x, scale: scale)
        s.selection = selection
        s.phase = .editing
        return s
    }

    // MARK: Size and pixels

    @Test func outputPixelsAreCanvasTimesScale() throws {
        for scale: CGFloat in [1, 2, 3] {
            let s = Fixture.session(Fixture.gradient(Int(600 * scale), Int(400 * scale)), scale: scale)
            s.selection = CGRect(x: 37, y: 41, width: 123, height: 77)
            s.phase = .editing
            for enabled in [false, true] {
                for ratio in Ratio.allCases {
                    for padding: CGFloat in [0, 48] {
                        s.style.enabled = enabled
                        s.style.ratio = ratio
                        s.style.padding = padding
                        let image = try #require(s.render())
                        let c = s.canvas
                        #expect(image.width == Int((c.width * scale - 1e-6).rounded(.up))
                                    && image.height == Int((c.height * scale - 1e-6).rounded(.up)),
                                "@\(scale)x bg=\(enabled) \(ratio) p\(padding): \(image.width)×\(image.height) for \(c)")
                    }
                }
            }
        }
    }

    @Test func exportIsPixelExactForWholePointSelections() throws {
        for scale: CGFloat in [1, 2] {
            let sel = CGRect(x: 301, y: 207, width: 160, height: 90)
            let s = session(scale: scale, selection: sel)
            let out = Pixels(try #require(s.render()))
            let src = Pixels(scale == 1 ? Self.coded1x : Self.coded2x)
            let dx = Int(sel.minX * scale), dy = Int(sel.minY * scale)
            var wrong = 0
            for y in stride(from: 0, to: out.height, by: 7) {
                for x in stride(from: 0, to: out.width, by: 7) where out[x, y] != src[x + dx, y + dy] { wrong += 1 }
            }
            #expect(wrong == 0, "@\(scale)x: \(wrong) sampled pixels differ")
        }
    }

    @Test func fractionalSelectionOriginStaysSharp() throws {
        for (scale, origin) in [(1.0, 10.5), (2.0, 10.25), (2.0, 10.1)] as [(CGFloat, CGFloat)] {
            let s = Fixture.session(Fixture.checker(Int(400 * scale), Int(300 * scale)), scale: scale)
            s.selection = CGRect(x: origin, y: origin, width: 100, height: 50)
            s.phase = .editing
            let out = Pixels(try #require(s.render()))
            var grey = 0
            for y in 2..<(out.height - 2) {
                for x in 2..<(out.width - 2) where !(out[x, y].r < 8 || out[x, y].r > 247) { grey += 1 }
            }
            print("FRACTIONAL @\(scale)x origin \(origin): \(grey) of \((out.width - 4) * (out.height - 4)) pixels resampled, e.g. \(out[10, 10])")
            #expect(grey == 0, "@\(scale)x origin \(origin)")
        }
    }

    @Test func blurRegionLinesUpWithThePixelatedImage() throws {
        for scale: CGFloat in [1, 2] {
            let sel = CGRect(x: 200, y: 100, width: 400, height: 300)
            let s = session(scale: scale, selection: sel)
            s.tool = .blur
            s.drag(pt(300, 200), pt(500, 350))
            let out = Pixels(try #require(s.render()))
            let pixelated = Pixels(s.pixelated), original = Pixels(s.image)
            var wrongInside = 0, wrongOutside = 0
            for y in stride(from: 0, to: out.height, by: 5) {
                for x in stride(from: 0, to: out.width, by: 5) {
                    let screen = pt(sel.minX + CGFloat(x) / scale, sel.minY + CGFloat(y) / scale)
                    let sx = Int(screen.x * scale), sy = Int(screen.y * scale)
                    if CGRect(x: 300, y: 200, width: 200, height: 150).insetBy(dx: 5, dy: 5).contains(screen) {
                        if !out[x, y].near(pixelated[sx, sy], 3) { wrongInside += 1 }
                    } else if !CGRect(x: 300, y: 200, width: 200, height: 150).insetBy(dx: -2, dy: -2).contains(screen) {
                        if out[x, y] != original[sx, sy] { wrongOutside += 1 }
                    }
                }
            }
            #expect(wrongInside == 0 && wrongOutside == 0, "@\(scale)x inside \(wrongInside), outside \(wrongOutside)")
        }
    }

    @Test func everyToolChangesTheExportedPixels() throws {
        let sel = CGRect(x: 200, y: 100, width: 600, height: 400)
        let plain = Pixels(try #require(session(scale: 2, selection: sel).render()))
        let s = session(scale: 2, selection: sel)
        s.annotateEverything(in: sel)
        #expect(s.annotations.map(\.tool) == [.arrow, .rect, .highlight, .blur, .pen, .step, .text])
        let marked = Pixels(try #require(s.render()))
        for a in s.annotations {
            let box = a.tool == .step || a.tool == .text ? CGRect(origin: a.points[0], size: .zero).insetBy(dx: -8, dy: -6)
                                                         : a.box.insetBy(dx: -2, dy: -2)
            var changed = 0
            for y in Int((box.minY - sel.minY) * 2)..<Int((box.maxY - sel.minY) * 2) {
                for x in Int((box.minX - sel.minX) * 2)..<Int((box.maxX - sel.minX) * 2) where marked[x, y] != plain[x, y] { changed += 1 }
            }
            #expect(changed > 20, "\(a.tool) changed \(changed) pixels")
        }
    }

    @Test func textBeingEditedIsCommittedAndExported() throws {
        let sel = CGRect(x: 200, y: 100, width: 600, height: 400)
        let plain = Pixels(try #require(session(scale: 1, selection: sel).render()))
        let s = session(scale: 1, selection: sel)
        s.tool = .text
        s.tap(pt(300, 300))
        s.draft = "Still typing"
        let shot = try #require(Shot(s))
        #expect(s.editingText == nil)
        #expect(shot.session.annotations.map(\.text) == ["Still typing"])
        let out = Pixels(shot.cgImage)
        var changed = 0
        for y in 190..<210 { for x in 100..<200 where out[x, y] != plain[x, y] { changed += 1 } }
        #expect(changed > 500, "label pixels changed: \(changed)")
    }

    @Test func emptySelectionRendersNothing() {
        let s = session(scale: 2, selection: .zero)
        #expect(s.render() == nil)
        #expect(Shot(s) == nil)
        s.selection = .null
        #expect(s.render() == nil)
        s.style.enabled = true                 // background only; Shiny.handle refuses empty selections first
        s.selection = .zero
        #expect(s.render().map { [$0.width, $0.height] } == [192, 192])
    }

    // MARK: Shot payloads

    @Test func pngCarriesThePointSizeAsDPI() throws {
        for scale: CGFloat in [1, 2, 3] {
            let s = Fixture.session(Fixture.gradient(Int(300 * scale), Int(200 * scale)), scale: scale)
            s.selection = CGRect(x: 10, y: 20, width: 120, height: 80)
            s.phase = .editing
            let shot = try #require(Shot(s))
            #expect(shot.size == CGSize(width: 120, height: 80))
            #expect(shot.image.size == CGSize(width: 120, height: 80))
            let png = try #require(shot.png)
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(props[kCGImagePropertyPixelWidth] as? Int == Int(120 * scale))
            #expect(props[kCGImagePropertyPixelHeight] as? Int == Int(80 * scale))
            let dpi = props[kCGImagePropertyDPIWidth] as? Double ?? 72   // no pHYs chunk means 72
            #expect(abs(dpi - 72 * scale) < 0.5, "@\(scale)x DPI \(dpi)")
        }
    }

    /// Copies to a private pasteboard so the user's clipboard is left alone.
    @Test func pasteboardPayloadsAreFullResolution() throws {
        let s = session(scale: 2, selection: CGRect(x: 100, y: 100, width: 300, height: 200))
        let shot = try #require(Shot(s))
        let pb = NSPasteboard(name: NSPasteboard.Name("ShinyScreenshotTests.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        shot.copy(to: pb)
        #expect(pb.types?.contains(.png) == true && pb.types?.contains(.tiff) == true)
        let pngData = try #require(pb.data(forType: .png))
        let png = try #require(NSBitmapImageRep(data: pngData))
        #expect(png.pixelsWide == 600 && png.pixelsHigh == 400)
        let tiffData = try #require(pb.data(forType: .tiff))
        let tiff = try #require(NSBitmapImageRep(data: tiffData))
        #expect(tiff.pixelsWide == 600 && tiff.pixelsHigh == 400, "TIFF \(tiff.pixelsWide)×\(tiff.pixelsHigh)")
        #expect(tiff.size == CGSize(width: 300, height: 200))
        let image = try #require(NSImage(pasteboard: pb))
        #expect(image.size == CGSize(width: 300, height: 200))
    }

    // MARK: Saving

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShinyScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveWritesATimestampedPNG() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shot = try #require(Shot(session(scale: 2, selection: CGRect(x: 0, y: 0, width: 64, height: 32))))
        let url = try #require(shot.save(to: dir))
        #expect(url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(url.lastPathComponent.wholeMatch(of: /Shiny Screenshot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}\.png/) != nil,
                "\(url.lastPathComponent)")
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(rep.pixelsWide == 128 && rep.pixelsHigh == 64)
    }

    @Test func twoSavesInTheSameSecondKeepBothFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try #require(Shot(session(scale: 1, selection: CGRect(x: 0, y: 0, width: 50, height: 50))))
        let second = try #require(Shot(session(scale: 1, selection: CGRect(x: 0, y: 0, width: 80, height: 20))))
        var urls: [URL?] = []
        for _ in 0..<5 {                       // retry if the pair straddles a second boundary
            for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: f) }
            let before = Int(Date().timeIntervalSince1970)
            urls = [first.save(to: dir), second.save(to: dir)]
            if Int(Date().timeIntervalSince1970) == before { break }
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(urls[0] != urls[1])
        #expect(files.count == 2)
    }

    /// Starting a drag writes nothing; each drop gets its own PNG.
    @Test func everyDragGetsItsOwnFile() async throws {
        let shot = try #require(Shot(session(scale: 1, selection: CGRect(x: 0, y: 0, width: 40, height: 40))))
        let files = { Set((try? FileManager.default.contentsOfDirectory(atPath: Shot.dragFolder.path)) ?? []) }
        let before = files()
        let items = [shot.dragItem(), shot.dragItem()]
        #expect(files() == before)
        for item in items {
            let size: Int = try await withCheckedThrowingContinuation { c in
                _ = item.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
                    c.resume(with: Result { try #require(url.flatMap { NSBitmapImageRep(data: try Data(contentsOf: $0)) }, "\(String(describing: error))").pixelsWide })
                }
            }
            #expect(size == 40)
        }
        #expect(files().subtracting(before).count == 2)
    }

    @Test func oldDragFilesAreCleared() throws {
        let old = Shot.dragFolder.appending(path: "old-\(UUID().uuidString)")
        let fresh = Shot.dragFolder.appending(path: "fresh-\(UUID().uuidString)")
        for dir in [old, fresh] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: fresh) }
        try FileManager.default.setAttributes([.creationDate: Date.now - 7200], ofItemAtPath: old.path)
        Shot.removeDragFiles(olderThan: 3600)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func saveIntoAMissingFolderFailsCleanly() throws {
        let shot = try #require(Shot(session(scale: 1, selection: CGRect(x: 0, y: 0, width: 10, height: 10))))
        #expect(shot.save(to: URL(filePath: "/nonexistent-\(UUID().uuidString)")) == nil)
    }

    // MARK: Huge canvases

    @Test func hugeRetinaCanvasTimingAndMemory() throws {
        let before = footprintMB()
        let image = timed("build 6016×3384 test image") { Fixture.gradient(6016, 3384) }
        let s = timed("Session incl. Capture.pixelate 6016×3384 @2x, incl. drawing") {
            let s = Fixture.session(image, scale: 2)
            _ = s.pixelated.dataProvider?.data
            return s
        }
        s.selectAll()
        s.annotateEverything(in: CGRect(x: 1000, y: 500, width: 1000, height: 700))
        // ImageRenderer's CGImage is lazy: reading its data is what actually draws it.
        let plain = try #require(timed("render 3008×1692 pt @2x, no background, incl. drawing") { s.render().map { _ = $0.dataProvider?.data; return $0 } })
        #expect(plain.width == 6016 && plain.height == 3384)
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // What Shiny.handle(.copy) does on the main thread: render and a lazy pasteboard promise. Encoding waits for a paste.
        let pb = NSPasteboard(name: NSPasteboard.Name("ShinyScreenshotTests.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        timed("copy path 6016×3384 (render + pasteboard promise + card thumbnail)") {
            guard let shot = Shot(s) else { return }
            shot.copy(to: pb)
            _ = shot.image
        }
        let shot = try #require(Shot(s))
        let png = try #require(timed("Shot.png 6016×3384") { shot.png })
        let tiff = try #require(timed("Shot.image.tiffRepresentation 6016×3384") { shot.image.tiffRepresentation })
        print("SIZE png \(png.count / 1_048_576) MB, tiff \(tiff.count / 1_048_576) MB")

        s.style = Style(enabled: true, backdrop: .silk, padding: 160, radius: 32, shadow: 0.8, ratio: .portrait)
        let styled = try #require(timed("render 3328×4160 pt @2x, wallpaper + portrait + 160 padding, incl. drawing") {
            s.render().map { _ = $0.dataProvider?.data; return $0 }
        })
        #expect(styled.width == Int(s.canvas.width * 2) && styled.height == Int(s.canvas.height * 2),
                "\(styled.width)×\(styled.height) for \(s.canvas)")
        let url = timed("Shot.save 6656×8320") { Shot(s)?.save(to: dir) }
        #expect(url != nil)
        print("MEMORY footprint before \(before) MB, after \(footprintMB()) MB")
    }
}
