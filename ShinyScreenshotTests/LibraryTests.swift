import Foundation
import Testing
@testable import ShinyScreenshot

/// Library: filtering, sorting and grouping, and keeping files and index in step.
struct LibraryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cal = Calendar(identifier: .gregorian)

    func item(_ hoursAgo: Double, _ w: Int, _ kind: CaptureMode, app: String?, fav: Bool = false) -> LibraryItem {
        LibraryItem(id: UUID(), date: now - hoursAgo * 3600, width: w, height: 100, scale: 2, kind: kind, app: app, favorite: fav)
    }

    var items: [LibraryItem] {
        [item(1, 300, .area, app: "Safari"), item(30, 100, .window, app: "Xcode", fav: true),
         item(2, 900, .fullScreen, app: "Safari"), item(24 * 10, 500, .scrolling, app: nil)]
    }

    @Test func sortsAndGroups() {
        var q = LibraryQuery(group: .none, sort: .newest)
        #expect(Library.arrange(items, q, now: now, calendar: cal)[0].items.map(\.width) == [300, 900, 100, 500])
        q.sort = .largest
        #expect(Library.arrange(items, q, now: now, calendar: cal)[0].items.map(\.width) == [900, 500, 300, 100])
        q.group = .kind
        #expect(Library.arrange(items, q, now: now, calendar: cal).map(\.title) == ["Area", "Window", "Full Screen", "Scrolling"])
        q.group = .app
        #expect(Library.arrange(items, q, now: now, calendar: cal).map(\.title) == ["Safari", "Unknown App", "Xcode"])
        q.group = .day
        q.sort = .oldest
        let days = Library.arrange(items, q, now: now, calendar: cal)
        #expect(days.count == 3 && days.first?.items.map(\.width) == [500])
    }

    @Test func filters() {
        func widths(_ q: LibraryQuery) -> Set<Int> {
            Set(Library.arrange(items, q, now: now, calendar: cal).flatMap(\.items).map(\.width))
        }
        #expect(widths(LibraryQuery(search: "SAF")) == [300, 900])
        #expect(widths(LibraryQuery(search: "scroll")) == [500])
        #expect(widths(LibraryQuery(kinds: [.window, .area])) == [300, 100])
        #expect(widths(LibraryQuery(favoritesOnly: true)) == [100])
        #expect(widths(LibraryQuery(period: .week)) == [300, 100, 900])
        #expect(Library.arrange(items, LibraryQuery(search: "nothing"), now: now, calendar: cal).isEmpty)
    }

    @Test func addsOnceSurvivesReloadAndDeletes() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LibraryTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = Library(folder: dir)
        var shot = Shot(Fixture.coded(40, 20), scale: 2, displayID: 1)
        shot.kind = .window
        shot.app = "Notes"
        await lib.add(shot)
        await lib.add(shot)
        #expect(lib.items.count == 1)
        let item = try #require(lib.items.first)
        #expect(item.width == 20 && item.height == 10 && item.kind == .window && item.app == "Notes")
        lib.toggleFavorite(item.id)
        let again = Library(folder: dir)
        #expect(again.items.map(\.id) == [item.id] && again.items[0].favorite)
        #expect(again.shot(item)?.cgImage.width == 40)
        again.delete([item.id])
        #expect(Library(folder: dir).items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: again.url(of: item).path))
    }
}

/// Reopening a Library capture: the pixels, annotations and background come back, and copying again updates the entry.
struct LibraryEditTests {
    @Test func reopenedCaptureRendersTheSameAndUpdatesItsEntry() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LibraryEditTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = Library(folder: dir)
        let s = Fixture.session(Fixture.coded(400, 300), scale: 2)
        s.selection = CGRect(x: 20, y: 30, width: 120, height: 80)
        s.phase = .editing
        s.annotations = [Annotation(tool: .rect, color: palette[4], points: [pt(30, 40), pt(90, 70)]),
                         Annotation(tool: .text, color: .mark, points: [pt(40, 50)], text: "Hi", size: 15, filled: true)]
        s.style.enabled = true
        s.style.backdrop = .nebula
        s.style.title = "Title"
        let first = try #require(Shot(s))
        await lib.add(first)
        let item = try #require(lib.items.first)
        #expect(item.editable == true)
        lib.rename(item.id, to: "  Login bug ")
        lib.setTags(item.id, "ui, , UI, v2")
        #expect(lib.items[0].name == "Login bug" && lib.items[0].tags == ["ui", "v2"])

        // Same screen: the whole screen comes back, and the export is identical.
        let again = try #require(Library(folder: dir).session(item, displayID: 0, fit: s.size))
        #expect(again.size == s.size && again.scale == 2 && again.selection == s.selection)
        #expect(again.style.backdrop == .nebula && again.annotations.count == 2)
        #expect(again.annotations[1].color == .mark && again.annotations[0].color == palette[4])
        let a = Pixels(first.cgImage), b = Pixels(try #require(Shot(again)).cgImage)
        #expect(a.width == b.width && a.height == b.height)
        for (x, y) in [(5, 5), (a.width / 2, a.height / 2), (a.width - 3, a.height - 3)] { #expect(a[x, y].near(b[x, y]), "\(x),\(y)") }
        // Moving the selection shows the rest of the screen, as in a fresh capture.
        again.style.enabled = false
        again.selection = CGRect(x: 150, y: 100, width: 40, height: 40)
        #expect(Pixels(try #require(Shot(again)).cgImage)[0, 0] == Pixels(Fixture.coded(400, 300))[300, 200])
        again.selection = s.selection
        again.style.enabled = true

        // Half the size: shrunk to fit, same pixels, markup in step, still pastes at its original size.
        let small = try #require(lib.session(item, displayID: 0, fit: CGSize(width: 100, height: 150)))
        // 100 × 75 of capture, centred on the 100 × 150 screen.
        #expect(small.size == CGSize(width: 100, height: 150) && small.scale == 4)
        #expect(small.selection == CGRect(x: 10, y: 52.5, width: 60, height: 40))
        #expect(small.annotations[0].points[0] == pt(15, 57.5) && small.annotations[1].size == 7.5)
        // Without a title, every size scales with it, so the export keeps its exact pixel size.
        small.style.title = ""
        again.style.title = ""
        let shrunk = try #require(Shot(small)), full = try #require(Shot(again))
        #expect(shrunk.size == full.size)
        #expect(shrunk.scale == 2 && shrunk.cgImage.width == full.cgImage.width && shrunk.cgImage.height == full.cgImage.height)
        again.style.title = "Title"

        // Copying the reopened capture replaces the entry, keeping its name and tags.
        again.annotations.removeLast()
        await lib.add(try #require(Shot(again)))
        #expect(lib.items.count == 1 && lib.items[0].name == "Login bug" && lib.items[0].updated != nil)
        #expect(lib.session(lib.items[0], displayID: 0, fit: s.size)?.annotations.count == 1)
    }

    @Test func capturesWithoutMarkupReopenAsTheirImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LibraryFlat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = Library(folder: dir)
        // A tall scrolling capture: 100 × 1000 points at 2×.
        var tall = Shot(Fixture.coded(200, 2000), scale: 2, displayID: 0)
        tall.kind = .scrolling
        await lib.add(tall)
        let item = try #require(lib.items.first)
        #expect(item.editable == false)
        let s = try #require(lib.session(item, displayID: 0, fit: CGSize(width: 1440, height: 900)))
        // Shrunk to the screen's height and centred on it, so the toolbar lays out as usual.
        #expect(s.phase == .editing && s.size == CGSize(width: 1440, height: 900) && s.shotID == item.id)
        #expect(s.selection == CGRect(x: 675, y: 0, width: 90, height: 900))
        s.annotations = [Annotation(tool: .rect, color: palette[0], points: [pt(685, 10), pt(725, 50)])]
        let marked = try #require(Shot(s))
        #expect(marked.cgImage.width == 200 && marked.cgImage.height == 2000 && marked.size == tall.size)
        // Marking it up makes it editable: the original underneath, the rectangle on top.
        await lib.add(marked)
        #expect(lib.items.count == 1 && lib.items[0].editable == true && lib.items[0].scale == 2)
        let back = try #require(lib.session(lib.items[0], displayID: 0, fit: CGSize(width: 1440, height: 900)))
        #expect(back.annotations.count == 1 && back.selection == s.selection)
        #expect(Pixels(back.image)[Int(back.selection.minX * back.scale), 0] == Pixels(tall.cgImage)[0, 0])
    }

    @Test func tagsFilterAndGroup() {
        let a = LibraryItem(id: UUID(), date: .now, width: 1, height: 1, scale: 1, kind: .area, name: "Alpha", tags: ["ui", "v2"])
        let b = LibraryItem(id: UUID(), date: .now, width: 2, height: 1, scale: 1, kind: .area, tags: ["v2"])
        let c = LibraryItem(id: UUID(), date: .now, width: 3, height: 1, scale: 1, kind: .area)
        let groups = Library.arrange([a, b, c], LibraryQuery(group: .tag))
        #expect(groups.map(\.title) == ["ui", "v2", "Untagged"] && groups[1].items.count == 2)
        #expect(Library.arrange([a, b, c], LibraryQuery(group: .none, tags: ["ui"]))[0].items.map(\.width) == [1])
        #expect(Library.arrange([a, b, c], LibraryQuery(search: "alp", group: .none))[0].items.map(\.width) == [1])
        #expect(Library.arrange([a, b, c], LibraryQuery(search: "V2", group: .none))[0].items.count == 2)
    }

    @Test func oldIndexWithoutNewFieldsStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LibraryOld-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        try Data().write(to: dir.appending(path: "\(id.uuidString).png"))
        let json = #"[{"id":"\#(id.uuidString)","date":0,"width":10,"height":5,"scale":2,"kind":"window","favorite":true}]"#
        try Data(json.utf8).write(to: dir.appending(path: "library.json"))
        let lib = Library(folder: dir)
        #expect(lib.items.count == 1 && lib.items[0].favorite && lib.items[0].tagList.isEmpty && lib.items[0].editable == nil)
    }
}
