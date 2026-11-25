import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One capture kept in the Library: a PNG in the Library folder plus what it was.
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    /// Points.
    var width: Int, height: Int
    var scale: CGFloat
    let kind: CaptureMode
    /// The app in front when the capture started.
    var app: String?
    /// The background's name, when it had one.
    var backdrop: String?
    var favorite = false
    // Optional, so indexes written before these existed still load.
    var name: String?
    var tags: [String]?
    /// Last edited, so thumbnails refresh.
    var updated: Date?
    /// Saved with its annotations, so it can be edited again.
    var editable: Bool?
    /// A video: the PNG is its poster, the MP4 sits beside it.
    var video: Bool?

    var file: String { "\(id.uuidString).png" }
    var isVideo: Bool { video == true }
    var area: Int { width * height }
    var title: String { name ?? app ?? kind.title }
    var tagList: [String] { tags ?? [] }
}

/// What reopening a capture needs besides the pixels: where the selection was, the markup and the background.
struct EditState: Codable {
    struct Mark: Codable {
        var tool: Tool
        /// sRGB hex.
        var color: Int
        var points: [CGPoint]
        var text: String
        var number: Int
        var size: CGFloat
        var filled: Bool
    }

    var selection: CGRect
    /// The frozen screen: its size in points and pixels per point.
    var screenSize: CGSize
    var scale: CGFloat
    /// Pixels per point the export is tagged with, when the session was shrunk to fit a smaller screen.
    var pasteScale: CGFloat?
    var windows: [CGRect]
    var marks: [Mark]
    var style: Style
    /// The clicked window, when the capture was a window on its own.
    var windowFrame: CGRect?

    init(_ s: Session) {
        selection = s.selection
        screenSize = s.size
        scale = s.scale
        pasteScale = s.pasteScale
        windows = s.windows.map(\.frame)
        style = s.style
        windowFrame = s.activeWindowShot?.frame
        marks = s.annotations.map {
            Mark(tool: $0.tool, color: hex($0.color), points: $0.points, text: $0.text, number: $0.number, size: $0.size, filled: $0.filled)
        }
    }
}

private func hex(_ c: Color) -> Int {
    guard let n = NSColor(c).usingColorSpace(.sRGB) else { return 0 }
    return [n.redComponent, n.greenComponent, n.blueComponent].reduce(0) { $0 << 8 | Int(($1 * 255).rounded()) }
}

enum LibraryGroup: String, CaseIterable, Identifiable {
    case none = "None", day = "Day", app = "App", kind = "Type", tag = "Tag"
    var id: Self { self }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest First", oldest = "Oldest First", largest = "Largest First", smallest = "Smallest First"
    var id: Self { self }
}

enum LibraryPeriod: String, CaseIterable, Identifiable {
    case any = "Any Time", today = "Today", week = "Last 7 Days", month = "Last 30 Days"
    var id: Self { self }
}

struct LibraryQuery: Equatable {
    var search = ""
    var group = LibraryGroup.day
    var sort = LibrarySort.newest
    /// Empty shows every kind.
    var kinds: Set<CaptureMode> = []
    var favoritesOnly = false
    var period = LibraryPeriod.any
    /// Empty shows every tag; otherwise captures with any of these.
    var tags: Set<String> = []
}

/// Captures saved for later, newest last on disk. Lives in Application Support, indexed by library.json.
@Observable
final class Library {
    static let shared = Library(folder: URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "ShinyScreenshot").appending(path: "Library"))

    private(set) var items: [LibraryItem] = []
    let folder: URL
    private var index: URL { folder.appending(path: "library.json") }

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try? Data(contentsOf: index)
        let saved = data.flatMap { try? JSONDecoder().decode([LibraryItem].self, from: $0) }
        // An index this version can't read is set aside, not overwritten by the next save.
        if data != nil, saved == nil {
            try? FileManager.default.moveItem(at: index, to: folder.appending(path: "library-\(Int(Date.now.timeIntervalSince1970)).json"))
        }
        // Files removed in Finder drop out of the Library.
        items = (saved ?? []).filter { FileManager.default.fileExists(atPath: url(of: $0).path) }
    }

    func url(of item: LibraryItem) -> URL { folder.appending(path: item.file) }
    /// The file to open, copy or drag: the MP4 for videos, else the PNG.
    func mediaURL(of item: LibraryItem) -> URL { item.isVideo ? files(item.id).movie : url(of: item) }
    func contains(_ id: UUID) -> Bool { items.contains { $0.id == id } }

    /// The image, the whole frozen screen, the window on its own, and the markup.
    /// For videos also the finished MP4, and for recordings the recording as it came, so it can be styled again.
    private func files(_ id: UUID) -> (image: URL, screen: URL, window: URL, edit: URL, movie: URL, source: URL) {
        let base = id.uuidString
        return (folder.appending(path: "\(base).png"), folder.appending(path: "\(base)-screen.png"),
                folder.appending(path: "\(base)-window.png"), folder.appending(path: "\(base)-edit.json"),
                folder.appending(path: "\(base).mp4"), folder.appending(path: "\(base)-source.mp4"))
    }

    /// Writes the files in the background; the item shows up once they are on disk.
    /// A shot already in the Library replaces its image and markup, keeping name, tags and star.
    func add(_ shot: Shot, video: URL? = nil) async {
        let existing = items.first { $0.id == shot.id }
        if existing != nil && shot.session == nil { return }
        var item = existing ?? LibraryItem(id: shot.id, date: shot.date, width: 0, height: 0, scale: shot.scale, kind: shot.kind, app: shot.app)
        item.width = Int(shot.size.width)
        item.height = Int(shot.size.height)
        item.scale = shot.scale
        item.backdrop = shot.backdrop
        item.updated = existing == nil ? nil : .now
        let s = shot.session
        let edit = s.map(EditState.init)
        // The whole screen, so a reopened capture can be moved and resized like a fresh one.
        let screen = s?.image
        let window = s?.activeWindowShot?.image
        item.editable = edit != nil
        let (cg, size, opaque, f) = (shot.cgImage, shot.size, shot.opaque, files(item.id))
        let editJSON = edit.flatMap { try? JSONEncoder().encode($0) }
        let written = await Task.detached {
            func png(_ image: CGImage?, _ url: URL, scale: CGFloat, opaque: Bool) -> Bool {
                guard let image else { try? FileManager.default.removeItem(at: url); return true }
                let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                guard let data = Shot.png(image, size: size, opaque: opaque) else { return false }
                return (try? data.write(to: url, options: .atomic)) != nil
            }
            guard png(cg, f.image, scale: CGFloat(cg.width) / size.width, opaque: opaque) else { return false }
            if let edit, let editJSON {
                // Without the screen the markup is useless; the capture then reopens as a flat image.
                guard png(screen, f.screen, scale: edit.scale, opaque: true),
                      png(window, f.window, scale: edit.scale, opaque: false) else { return false }
                try? editJSON.write(to: f.edit, options: .atomic)
            }
            return true
        }.value
        guard written || item.editable == true else { return }
        if !written { item.editable = false }
        if let video {
            // The recording as it came, kept once; the finished video replaces the last one.
            let source = shot.session?.video
            let ok = await Task.detached {
                let fm = FileManager.default
                if let source, source != f.source, !fm.fileExists(atPath: f.source.path) { try? fm.copyItem(at: source, to: f.source) }
                try? fm.removeItem(at: f.movie)
                return (try? fm.copyItem(at: video, to: f.movie)) != nil
            }.value
            guard ok else { return }
            item.video = true
        }
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            item.favorite = items[i].favorite
            item.name = items[i].name
            item.tags = items[i].tags
            items[i] = item
        } else {
            items.append(item)
        }
        saveIndex()
    }

    /// The capture rebuilt as a live session that fits `fit` points: the frozen screen with its selection and
    /// editable markup, or, for captures saved without them, the image itself to draw on.
    func session(_ item: LibraryItem, displayID: CGDirectDisplayID, fit: CGSize) -> Session? {
        let f = files(item.id)
        if item.editable == true,
           let e = (try? Data(contentsOf: f.edit)).flatMap({ try? JSONDecoder().decode(EditState.self, from: $0) }),
           let screen = Self.image(f.screen) {
            let k = Self.fitting(e.screenSize, in: fit)
            let scale = e.scale / k
            let (image, size, o) = Self.padded(screen, scale: scale, size: e.screenSize * k, to: fit)
            func at(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k + o.x, y: p.y * k + o.y) }
            func at(_ r: CGRect) -> CGRect { CGRect(origin: at(r.origin), size: r.size * k) }
            let s = Session(Capture.Frozen(image: image, scale: scale, size: size,
                                           windows: e.windows.map { .init(id: kCGNullWindowID, frame: at($0)) }),
                            displayID: displayID)
            s.pasteScale = e.pasteScale ?? e.scale
            s.selection = at(e.selection)
            s.phase = .editing
            s.style = e.style
            s.style.padding *= k
            s.style.radius *= k
            s.annotations = e.marks.map { m in
                Annotation(tool: m.tool, color: Color(hex: m.color), points: m.points.map(at),
                           text: m.text, number: m.number, size: m.size * k, filled: m.filled)
            }
            if let frame = e.windowFrame, let window = Self.image(f.window) {
                s.windowShot = Capture.WindowShot(image: window, pixelated: Capture.pixelate(window, scale: s.scale) ?? Capture.grey,
                                                  frame: at(frame), selection: s.selection)
            }
            return identify(s, as: item)
        }
        guard let image = Self.image(f.image) else { return nil }
        return identify(Self.flatSession(image, scale: item.scale, displayID: displayID, fit: fit), as: item)
    }

    private func identify(_ s: Session, as item: LibraryItem) -> Session {
        // A recording reopens to be styled again from the recording as it came.
        let source = files(item.id).source
        if item.isVideo, FileManager.default.fileExists(atPath: source.path) { s.video = source }
        s.mode = item.kind
        s.app = item.app
        s.shotID = item.id
        return s
    }

    /// A finished image as a session of its own, all of it selected, to draw on.
    /// Shrunk (more pixels per point, the same pixels) when it is bigger than `fit`, like a scrolling capture.
    static func flatSession(_ image: CGImage, scale: CGFloat, displayID: CGDirectDisplayID, fit: CGSize) -> Session {
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let k = fitting(natural, in: fit)
        let (screen, size, o) = padded(image, scale: scale / k, size: natural * k, to: fit)
        let s = Session(Capture.Frozen(image: screen, scale: scale / k, size: size, windows: []), displayID: displayID)
        s.pasteScale = scale
        s.selection = CGRect(origin: o, size: natural * k)
        s.phase = .editing
        return s
    }

    /// A frozen screen smaller than `fit`, centred in a dark one that size, so the toolbar and panels lay out as on a
    /// real screen. Returns the image, its size in points and where the original now starts.
    private static func padded(_ image: CGImage, scale: CGFloat, size: CGSize, to fit: CGSize) -> (CGImage, CGSize, CGPoint) {
        guard size.width < fit.width || size.height < fit.height else { return (image, size, .zero) }
        let full = CGSize(width: max(size.width, fit.width), height: max(size.height, fit.height))
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let o = CGPoint(x: snap((full.width - size.width) / 2), y: snap((full.height - size.height) / 2))
        let w = Int((full.width * scale).rounded()), h = Int((full.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (image, size, .zero) }
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Core Graphics counts up from the bottom.
        let x = (o.x * scale).rounded(), y = CGFloat(h) - (o.y * scale).rounded() - CGFloat(image.height)
        ctx.draw(image, in: CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let padded = ctx.makeImage() else { return (image, size, .zero) }
        return (padded, CGSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale), o)
    }

    /// How much to shrink `size` so it fits, never enlarging.
    private static func fitting(_ size: CGSize, in fit: CGSize) -> CGFloat {
        min(1, fit.width / size.width, fit.height / size.height)
    }

    private static func image(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[i].name = n.isEmpty ? nil : n
        saveIndex()
    }

    /// Comma-separated; duplicates and blanks dropped.
    func setTags(_ id: UUID, _ text: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var seen = Set<String>()
        let tags = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        items[i].tags = tags.isEmpty ? nil : tags
        saveIndex()
    }

    var allTags: [String] {
        Array(Set(items.flatMap(\.tagList))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func toggleFavorite(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].favorite.toggle()
        saveIndex()
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids {
            let f = files(id)
            for url in [f.image, f.screen, f.window, f.edit, f.movie, f.source] { try? FileManager.default.removeItem(at: url) }
        }
        items.removeAll { ids.contains($0.id) }
        saveIndex()
    }

    /// The saved image as a Shot, to copy or pin.
    func shot(_ item: LibraryItem) -> Shot? {
        guard let cg = Self.image(url(of: item)) else { return nil }
        return Shot(cg, scale: item.scale, displayID: CGMainDisplayID(), opaque: false)
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: index, options: .atomic)
    }

    /// Filters, sorts and groups for the Library window. Groups without a title mean no grouping.
    static func arrange(_ items: [LibraryItem], _ q: LibraryQuery, now: Date = .now, calendar: Calendar = .current)
        -> [(title: String, items: [LibraryItem])] {
        let search = q.search.trimmingCharacters(in: .whitespaces)
        let since: Date? = switch q.period {
        case .any: nil
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        }
        let kept = items.filter { i in
            (q.kinds.isEmpty || q.kinds.contains(i.kind))
                && (!q.favoritesOnly || i.favorite)
                && (since.map { i.date >= $0 } ?? true)
                && (q.tags.isEmpty || !q.tags.isDisjoint(with: i.tagList))
                && (search.isEmpty || ([i.name ?? "", i.app ?? "", i.kind.title, i.backdrop ?? "", "\(i.width)×\(i.height)", i.isVideo ? "Video" : ""] + i.tagList)
                    .contains { $0.localizedStandardContains(search) })
        }
        let sorted = kept.sorted { a, b in
            switch q.sort {
            case .newest: a.date > b.date
            case .oldest: a.date < b.date
            case .largest: a.area != b.area ? a.area > b.area : a.date > b.date
            case .smallest: a.area != b.area ? a.area < b.area : a.date > b.date
            }
        }
        switch q.group {
        case .none:
            return sorted.isEmpty ? [] : [("", sorted)]
        case .day:
            let days = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
            return days.keys.sorted(by: q.sort == .oldest ? (<) : (>)).map { day in
                let title = calendar.isDateInToday(day) ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday"
                    : day.formatted(date: .complete, time: .omitted)
                return (title, days[day]!)
            }
        case .app:
            let apps = Dictionary(grouping: sorted) { $0.app ?? "Unknown App" }
            return apps.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, apps[$0]!) }
        case .kind:
            return CaptureMode.kept.compactMap { k in
                let these = sorted.filter { $0.kind == k }
                return these.isEmpty ? nil : (k.title, these)
            }
        case .tag:
            // A capture shows under each of its tags.
            let tags = Set(sorted.flatMap(\.tagList)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let untagged = sorted.filter { $0.tagList.isEmpty }
            return tags.map { t in (t, sorted.filter { $0.tagList.contains(t) }) } + (untagged.isEmpty ? [] : [("Untagged", untagged)])
        }
    }
}

private func * (p: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }
private func * (s: CGSize, k: CGFloat) -> CGSize { CGSize(width: s.width * k, height: s.height * k) }
private func * (r: CGRect, k: CGFloat) -> CGRect { CGRect(origin: r.origin * k, size: r.size * k) }

extension CaptureMode {
    /// What the Library records; capturing the last area again counts as an area.
    static let kept: [CaptureMode] = [.area, .window, .fullScreen, .scrolling, .recording]

    var title: String {
        switch self {
        case .area, .again: "Area"
        case .window: "Window"
        case .fullScreen: "Full Screen"
        case .scrolling: "Scrolling"
        case .recording: "Recording"
        }
    }

    var symbol: String {
        switch self {
        case .area, .again: "rectangle.dashed"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .scrolling: "arrow.up.and.down.text.horizontal"
        case .recording: "record.circle"
        }
    }
}

struct LibraryView: View {
    var library = Library.shared
    @AppStorage("library.group") private var group = LibraryGroup.day
    @AppStorage("library.sort") private var sort = LibrarySort.newest
    @State private var query = LibraryQuery()
    @State private var selection: UUID?
    @State private var renaming: LibraryItem?
    @State private var tagging: LibraryItem?
    @State private var draft = ""

    private var arranged: [(title: String, items: [LibraryItem])] {
        var q = query
        q.group = group
        q.sort = sort
        return Library.arrange(library.items, q)
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            let groups = arranged
            if groups.isEmpty {
                ContentUnavailableView {
                    Label(library.items.isEmpty ? "No captures yet" : "Nothing matches", systemImage: "photo.stack")
                } description: {
                    Text(library.items.isEmpty
                         ? "Click the Library button on the card after a capture, or turn on “Keep every capture in the Library” in Settings."
                         : "Try another search or filter.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                        ForEach(groups, id: \.title) { g in
                            Section {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                                    ForEach(g.items) { cell($0) }
                                }
                                .padding(.horizontal, 16)
                            } header: {
                                if !g.title.isEmpty {
                                    HStack {
                                        Text(g.title).font(.headline)
                                        Text("\(g.items.count)").foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 6)
                                    .background(.bar)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onTapGesture { selection = nil }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onDeleteCommand { if let selection { library.delete([selection]) } }
        .alert("Rename", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField("Name", text: $draft)
            Button("Rename") { if let renaming { library.rename(renaming.id, to: draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to show the app’s name.")
        }
        .alert("Tags", isPresented: Binding { tagging != nil } set: { if !$0 { tagging = nil } }) {
            TextField("bug, onboarding, v2", text: $draft)
            Button("Save") { if let tagging { library.setTags(tagging.id, draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Separate tags with commas.")
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            TextField("Search name, tag, app, type, size", text: $query.search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Picker("Group", selection: $group) {
                ForEach(LibraryGroup.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Menu {
                Picker("Date", selection: $query.period) {
                    ForEach(LibraryPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Section("Type") {
                    ForEach(CaptureMode.kept, id: \.self) { k in
                        Toggle(k.title, isOn: Binding {
                            query.kinds.contains(k)
                        } set: { on in
                            if on { query.kinds.insert(k) } else { query.kinds.remove(k) }
                        })
                    }
                }
                let tags = library.allTags
                if !tags.isEmpty {
                    Section("Tag") {
                        ForEach(tags, id: \.self) { t in
                            Toggle(t, isOn: Binding {
                                query.tags.contains(t)
                            } set: { on in
                                if on { query.tags.insert(t) } else { query.tags.remove(t) }
                            })
                        }
                    }
                }
                Divider()
                Toggle("Favourites Only", isOn: $query.favoritesOnly)
                Button("Clear Filters") {
                    query.tags = []
                    query.kinds = []
                    query.period = .any
                    query.favoritesOnly = false
                }
            } label: {
                let filtering = !query.kinds.isEmpty || !query.tags.isEmpty || query.period != .any || query.favoritesOnly
                Label("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            Spacer()
            Text("\(library.items.count) captures").foregroundStyle(.secondary).font(.callout)
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.open(library.folder) }
                .labelStyle(.iconOnly)
                .help("Open the Library folder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func cell(_ item: LibraryItem) -> some View {
        let url = library.mediaURL(of: item)
        let selected = selection == item.id
        return VStack(alignment: .leading, spacing: 6) {
            // Every tile the same shape, the capture filling it from the top, so the grid lines up.
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .top) { LibraryThumbnail(url: library.url(of: item), version: item.updated) }
                .background(.quaternary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .overlay(alignment: .topTrailing) {
                    Button { library.toggleFavorite(item.id) } label: {
                        Image(systemName: item.favorite ? "star.fill" : "star")
                            .foregroundStyle(item.favorite ? .yellow : .white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help(item.favorite ? "Remove from favourites" : "Add to favourites")
                }
                .overlay {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 4)
                    }
                }
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            HStack(spacing: 4) {
                Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                Text(item.title).lineLimit(1).fontWeight(.medium)
            }
            .font(.callout)
            Text("\(item.date.formatted(date: .omitted, time: .shortened)) · \(item.width) × \(item.height)" + (item.backdrop.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !item.tagList.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tagList, id: \.self) { t in
                        Button(t) { query.tags = [t] }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .help("Show only “\(t)”")
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onTapGesture { selection = item.id }
        .contextMenu {
            Button(item.isVideo ? "Edit Video" : item.editable == true ? "Edit Annotations" : "Mark Up") { Shiny.shared.edit(item) }
            if item.isVideo {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                }
            } else {
                Button("Copy") { library.shot(item)?.copy() }
                Button("Pin") { if let s = library.shot(item) { Shiny.shared.pin(s) } }
            }
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Rename…") {
                draft = item.name ?? ""
                renaming = item
            }
            Button("Tags…") {
                draft = item.tagList.joined(separator: ", ")
                tagging = item
            }
            Button(item.favorite ? "Remove from Favourites" : "Add to Favourites") { library.toggleFavorite(item.id) }
            Divider()
            Button("Delete", role: .destructive) { library.delete([item.id]) }
        }
    }
}

/// A downscaled preview, decoded off the main thread and kept for the session.
private struct LibraryThumbnail: View {
    let url: URL
    /// Changes when the capture is edited, so the old preview isn't reused.
    let version: Date?
    @State private var image: CGImage?

    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImage>()
    private var key: NSString { "\(url.path)#\(version?.timeIntervalSince1970 ?? 0)" as NSString }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: key) {
            if let hit = Self.cache.object(forKey: key) { image = hit; return }
            let made = await Task.detached { [url] in
                CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
                    CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                kCGImageSourceThumbnailMaxPixelSize: 560,
                                                                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                }
            }.value
            if let made { Self.cache.setObject(made, forKey: key) }
            image = made
        }
    }
}
