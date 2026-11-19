import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

@main
struct ShinyScreenshotApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Shiny Screenshot", image: "MenuBarIcon") { MenuContent() }
    }
}

private struct MenuContent: View {
    @AppStorage(HotkeyAction.area.defaultsKey) private var area = HotkeyAction.area.standard
    @AppStorage(HotkeyAction.window.defaultsKey) private var window = HotkeyAction.window.standard
    @AppStorage(HotkeyAction.again.defaultsKey) private var again = HotkeyAction.again.standard
    private let shiny = Shiny.shared

    var body: some View {
        if let version = Updates.shared.available {
            Button("Update to \(version)…") { Updates.shared.check() }
            Divider()
        }
        Button("Capture Area") { shiny.capture() }
            .keyboardShortcut(area.menuShortcut)
        Button("Capture Window") { shiny.capture(.window) }
            .keyboardShortcut(window.menuShortcut)
        Button("Capture Last Area Again") { shiny.capture(.again) }
            .keyboardShortcut(again.menuShortcut)
            .disabled(shiny.lastArea == nil)
        Button("Capture Full Screen") { shiny.capture(.fullScreen) }
        Button("Capture Scrolling Area") { shiny.capture(.scrolling) }
        Button("Record Screen Area") { shiny.capture(.recording) }
        Menu("Capture After Delay") {
            ForEach([3, 5, 10], id: \.self) { n in
                Button("\(n) Seconds") { shiny.capture(after: n) }
            }
        }
        Divider()
        Menu("Recent") {
            ForEach(shiny.recent.indices, id: \.self) { i in
                let shot = shiny.recent[i]
                Button { shiny.reopen(shot) } label: {
                    Label { Text(shot.caption) } icon: { Image(nsImage: shot.thumbnail) }
                }
            }
            Divider()
            Button("Clear") { shiny.recent = [] }
        }
        .disabled(shiny.recent.isEmpty)
        Button("Library…") { shiny.showLibrary() }
            .keyboardShortcut("l")
        Divider()
        Button("Settings…") { Shiny.shared.showSettings() }
            .keyboardShortcut(",")
        Button("Check for Updates…") { Updates.shared.check() }
        Divider()
        Button("Quit Shiny Screenshot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Shot.removeOldDragFiles()
        _ = Updates.shared
        Shiny.shared.registerShortcuts()
        if !Shiny.shared.isRegistered(.area) {
            let key = Shortcut.saved.display
            let alert = NSAlert()
            alert.messageText = "\(key) is already taken"
            alert.informativeText = "Another app uses \(key). Pick another shortcut in Settings, or capture from the Shiny Screenshot icon in the menu bar."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { Shiny.shared.showSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LazyImage.current?.resolve()
    }
}

enum OverlayAction { case copy, save, pin, scroll, record, video, pickImage, cancel }

enum CaptureMode: String, Codable { case area, window, again, fullScreen, scrolling, recording }

/// Owns the capture overlay and the floating cards and pins it leaves behind.
@Observable
final class Shiny {
    static let shared = Shiny()

    /// Newest first. Only the newest keeps its session (the whole frozen screen) for Edit; the rest keep just their image.
    var recent: [Shot] = []
    /// The last copied, saved or pinned selection and its background, for capturing the same area again.
    private(set) var lastArea: (rect: CGRect, style: Style)?

    private var overlay: NSWindow?
    private var session: Session?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var panels: [NSWindow] = []
    private var settings: NSWindow?
    private var library: NSWindow?
    private var hotkeys: [HotkeyAction: Hotkey] = [:]
    /// The image picker is open over the overlay, so losing key status doesn't close it.
    private var picking = false
    /// From the hotkey until the overlay closes (or an alert is dismissed), so a second press can't start a second capture.
    private var busy = false

    func capture(_ mode: CaptureMode = .area, after delay: Int = 0) {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else { return askForPermission() }
        guard let screen = Self.screenUnderMouse, let id = screen.displayID else { return }
        if delay > 0 { return countdown(delay, on: screen) { [weak self] in self?.capture(mode) } }
        let scale = screen.backingScaleFactor
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        busy = true
        Task {
            do {
                let session = Session(try await Capture.freeze(displayID: id, scale: scale), displayID: id)
                session.mode = mode == .again ? .area : mode
                session.app = app
                switch mode {
                case .area: break
                case .window: session.windowsOnly = true
                case .scrolling: session.scrolling = true
                case .recording: session.recording = true
                case .fullScreen: session.selectAll()
                case .again:
                    // Clipped to this screen; if none of it is here, select as usual.
                    if let last = lastArea, case let r = last.rect.intersection(session.bounds),
                       r.width >= minSelectionSide, r.height >= minSelectionSide {
                        session.selection = r
                        session.style = last.style
                        session.phase = .editing
                    }
                }
                busy = false
                open(session)
            } catch {
                Self.explainFailure(error)
                busy = false
            }
        }
    }

    private static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }

    /// Registers every saved shortcut (⇧⌘2 for an area by default: free on macOS, unlike ⇧⌘3/4/5).
    func registerShortcuts() {
        for a in HotkeyAction.allCases {
            hotkeys[a]?.unregister()
            let s = Shortcut.saved(a)
            let mode: CaptureMode = switch a {
            case .area: .area
            case .window: .window
            case .again: .again
            }
            hotkeys[a] = Hotkey(keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in self?.capture(mode) }
        }
    }

    func unregisterShortcuts() {
        for h in hotkeys.values { h.unregister() }
    }

    /// False when another app owns the shortcut.
    func isRegistered(_ a: HotkeyAction) -> Bool { hotkeys[a]?.isRegistered ?? false }

    private func countdown(_ seconds: Int, on screen: NSScreen, then go: @escaping () -> Void) {
        busy = true
        weak var panel: NSPanel?
        let p = makePanel(CountdownView(seconds: seconds) { [weak self] finished in
            guard let self, let panel else { return }
            self.close(panel)
            self.busy = false
            if finished { go() }
        })
        panel = p
        p.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - p.frame.width / 2, y: screen.visibleFrame.maxY - p.frame.height))
        p.orderFrontRegardless()
    }

    /// Shows a recent capture's card again: copy, save, pin or edit it from there.
    func reopen(_ shot: Shot) {
        showCard(shot, title: "Captured at \(shot.date.formatted(date: .omitted, time: .shortened))")
    }

    private func remember(_ shot: Shot) {
        let older = recent.filter { $0.session == nil || $0.session !== shot.session }.prefix(4).map(\.withoutSession)
        recent = [shot] + older
        // A capture reopened from the Library goes back into its entry.
        if UserDefaults.standard.bool(forKey: "keepInLibrary") || Library.shared.contains(shot.id) {
            Task { await Library.shared.add(shot) }
        }
    }

    /// Reopens a Library capture on the screen under the mouse, every annotation editable again.
    func edit(_ item: LibraryItem) {
        guard !busy, overlay == nil, let screen = Self.screenUnderMouse, let id = screen.displayID,
              let s = Library.shared.session(item, displayID: id, fit: screen.frame.size) else { return }
        open(s)
    }

    func showLibrary() {
        if library?.isVisible != true {
            let window = NSWindow(contentViewController: NSHostingController(rootView: LibraryView()))
            window.title = "Library"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(CGSize(width: 900, height: 620))
            window.isReleasedWhenClosed = false
            window.center()
            // Puts it back where it was last time, if it was moved.
            window.setFrameAutosaveName("Library")
            library = window
        }
        NSApp.activate()
        library?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settings?.isVisible != true {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Shiny Screenshot Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }

    private func open(_ s: Session) {
        guard overlay == nil, let screen = s.screen else { return }
        busy = true
        let window = OverlayWindow(screen: screen)
        window.contentView = NSHostingView(rootView: OverlayView(s: s) { [weak self] in self?.handle($0, s) })
        window.makeKeyAndOrderFront(nil)
        overlay = window
        session = s
        s.preparePixelated()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event, s) ?? event
        }
        // Clicking another app (say, on a second display) takes the keyboard away: cancel instead of leaving Esc dead.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.picking != true { self?.closeOverlay() } }
        }
    }

    private func closeOverlay() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        resignObserver = nil
        keyMonitor = nil
        overlay?.orderOut(nil)
        overlay = nil
        session?.releasePixelated()
        session = nil
        busy = false
    }

    /// Returns nil when the key was handled.
    private func handleKey(_ e: NSEvent, _ s: Session) -> NSEvent? {
        if s.editingText != nil {
            // Keys belong to the label being typed, unless its field never got focus.
            if overlay?.firstResponder is NSText { return e }
            s.commitText()
        }
        // Typing in the background panel's title and description; Esc and Return still close and copy.
        if overlay?.firstResponder is NSText, e.keyCode != UInt16(kVK_Escape), e.keyCode != UInt16(kVK_Return) { return e }
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd, Self.letter(e)) {
        case (UInt16(kVK_Escape), _, _):
            if s.tool != nil { s.tool = nil } else if s.style.enabled { s.style.enabled = false } else { closeOverlay() }
        case (UInt16(kVK_Return), _, _), (UInt16(kVK_ANSI_KeypadEnter), _, _), (_, true, "c"):
            handle(s.scrolling ? .scroll : s.recording ? .record : .copy, s)
        case _ where s.scrolling || s.recording:
            return e
        case (_, true, "z"):
            s.undo()
        case (_, true, "s"):
            handle(.save, s)
        case (_, false, let key):
            guard s.phase == .editing, let tool = Tool.allCases.first(where: { $0.key == key }) else { return e }
            s.tool = s.tool == tool ? nil : tool
        default:
            return e
        }
        return nil
    }

    /// The letter typed, or for non-Latin layouts (Cyrillic, Greek…) the letter at that key on a US keyboard.
    private static func letter(_ e: NSEvent) -> String {
        let typed = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if let c = typed.first, typed.count == 1, c.isASCII, c.isLetter { return typed }
        return usLetters[Int(e.keyCode)] ?? typed
    }

    private static let usLetters: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_H: "h", kVK_ANSI_N: "n",
        kVK_ANSI_P: "p", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_Z: "z",
    ]

    private func handle(_ action: OverlayAction, _ s: Session) {
        if action == .cancel { return closeOverlay() }
        if action == .pickImage { return pickImage(for: s) }
        guard !s.selection.isEmpty else { return }
        if action == .scroll {
            closeOverlay()
            return scroll(s.selection, on: s)
        }
        if action == .record {
            closeOverlay()
            return record(s.selection, on: s)
        }
        if s.video != nil || action == .video {
            guard action != .pin else { return }
            closeOverlay()
            return makeVideo(s, still: s.video == nil, copy: action == .copy)
        }
        guard let shot = Shot(s) else { return }
        closeOverlay()
        lastArea = (s.selection, s.style)
        remember(shot)
        switch action {
        case .copy: shot.copy(); showCard(shot, title: "Copied to clipboard")
        case .save: showSaved(shot)
        case .pin: pin(shot)
        case .scroll, .record, .video, .pickImage, .cancel: break
        }
    }

    /// Records `area` until Stop, then opens the first frame on the overlay to mark up and style; Copy or Save exports the video.
    private func record(_ area: CGRect, on s: Session) {
        guard let screen = s.screen else { return }
        let defaults = UserDefaults.standard
        guard let recorder = try? ScreenRecorder(area: area, scale: s.scale, sound: defaults.bool(forKey: "recordSound")) else { return }
        busy = true
        let frame = CGRect(x: screen.frame.minX + area.minX, y: screen.frame.maxY - area.maxY, width: area.width, height: area.height)
        let outline = makePanel(Rectangle().strokeBorder(.red, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: frame.width + 8, height: frame.height + 8))
        outline.ignoresMouseEvents = true
        outline.setFrameOrigin(CGPoint(x: frame.minX - 4, y: frame.minY - 4))
        weak var bar: NSPanel?
        func end() {
            close(outline)
            if let bar { close(bar) }
            busy = false
        }
        let b = makePanel(RecordingBar(stop: { [weak self] in
            guard let self, bar != nil else { return }
            end()
            Task {
                guard let url = await recorder.stop(), let poster = await Video.poster(url) else { return }
                let next = Library.flatSession(poster, scale: s.scale, displayID: s.displayID, fit: screen.frame.size)
                next.video = url
                next.mode = .recording
                next.app = s.app
                self.open(next)
            }
        }, cancel: {
            guard bar != nil else { return }
            end()
            Task { await recorder.cancel() }
        }))
        bar = b
        let below = frame.minY - b.frame.height
        let y = below > screen.visibleFrame.minY ? below : min(frame.maxY, screen.visibleFrame.maxY - b.frame.height)
        b.setFrameOrigin(CGPoint(x: frame.midX - b.frame.width / 2, y: y))
        outline.orderFrontRegardless()
        b.orderFrontRegardless()
        let cursor = defaults.object(forKey: "recordCursor") as? Bool ?? true
        Task {
            do {
                try await recorder.start(area: area, displayID: s.displayID, scale: s.scale, cursor: cursor)
            } catch {
                end()
                Self.explainFailure(error)
            }
        }
    }

    /// A video of the session: the still with its camera move, or the recording with its background. Copy puts the file on the
    /// clipboard; Save writes it to the save folder.
    private func makeVideo(_ s: Session, still: Bool, copy: Bool) {
        s.commitText()
        let job = VideoJob()
        let poster = s.render().map { NSImage(cgImage: $0, size: s.canvas) } ?? NSImage()
        let temp = FileManager.default.temporaryDirectory.appending(path: Bundle.main.bundleIdentifier ?? "ShinyScreenshot").appending(path: "Videos")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let url = Video.newFile(in: copy ? temp : Shot.folder, prefix: still ? "Shiny Video" : "Shiny Recording")
        weak var panel: NSPanel?
        let p = makePanel(VideoCard(job: job, poster: poster, title: copy ? "Video copied to clipboard" : "Saved to \(Shot.folderName)") { [weak self] in
            if let panel { self?.close(panel) }
        })
        panel = p
        if let screen = s.screen { p.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY)) }
        p.orderFrontRegardless()
        Task {
            do {
                if still {
                    try await Video.motion(s, to: url) { job.progress = $0 }
                } else {
                    try await Video.styled(s, to: url)
                }
                job.url = url
                if copy {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                }
            } catch {
                job.failed = true
            }
        }
    }

    /// Picks a picture for the background, above the overlay.
    private func pickImage(for s: Session) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a background picture"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        picking = true
        let ok = panel.runModal() == .OK
        picking = false
        if ok, let url = panel.url, let path = Pictures.keep(url) {
            s.style.imagePath = path
            s.style.fill = .image
        }
        overlay?.makeKeyAndOrderFront(nil)
    }

    /// Records `area` while you scroll, with an outline around it and Done and Cancel below. Done copies the tall result.
    private func scroll(_ area: CGRect, on s: Session) {
        guard let screen = s.screen else { return }
        busy = true
        let rec = Scrolling(area: area, displayID: s.displayID, scale: s.scale)
        // Cocoa puts the origin at the bottom left.
        let frame = CGRect(x: screen.frame.minX + area.minX, y: screen.frame.maxY - area.maxY, width: area.width, height: area.height)
        let outline = makePanel(Rectangle().strokeBorder(Color.mark, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: frame.width + 8, height: frame.height + 8))
        outline.ignoresMouseEvents = true
        outline.setFrameOrigin(CGPoint(x: frame.minX - 4, y: frame.minY - 4))
        weak var bar: NSPanel?
        func end() {
            close(outline)
            if let bar { close(bar) }
            busy = false
        }
        let b = makePanel(ScrollingBar(s: rec, done: { [weak self] in
            guard let self, bar != nil else { return }
            end()
            Task {
                guard let image = await rec.finish() else { return }
                var shot = Shot(image, scale: s.scale, displayID: s.displayID)
                shot.kind = .scrolling
                shot.app = s.app
                self.remember(shot)
                shot.copy()
                self.showCard(shot, title: "Copied to clipboard")
            }
        }, cancel: {
            guard bar != nil else { return }
            rec.cancel()
            end()
        }))
        bar = b
        let below = frame.minY - b.frame.height
        let y = below > screen.visibleFrame.minY ? below : min(frame.maxY, screen.visibleFrame.maxY - b.frame.height)
        b.setFrameOrigin(CGPoint(x: frame.midX - b.frame.width / 2, y: y))
        outline.orderFrontRegardless()
        b.orderFrontRegardless()
        rec.start()
    }

    private func showSaved(_ shot: Shot) {
        Task {
            let saved = await shot.saveInBackground() != nil
            showCard(shot, title: saved ? "Saved to \(Shot.folderName)" : "Couldn't save to \(Shot.folderName)")
        }
    }

    private func showCard(_ shot: Shot, title: String) {
        guard let screen = shot.screen else { return }
        // Weak: the panel's view holds this closure, and `panels` keeps the panel alive while it is shown.
        weak var panel: NSPanel?
        let card = CardView(title: title, image: shot.image, inLibrary: Library.shared.contains(shot.id),
                            drag: shot.dragItem) { [weak self] action in
            guard let self, let panel else { return }
            // Stays open: the card's button turns into a check.
            if action == .library { Task { await Library.shared.add(shot) }; return }
            self.close(panel)
            switch action {
            case .copy: shot.copy()
            case .save: self.showSaved(shot)
            case .pin: self.pin(shot)
            case .edit: self.edit(shot)
            case .dismiss, .library: break
            }
        }
        let p = makePanel(card)
        panel = p
        p.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY))
        p.orderFrontRegardless()
    }

    /// Opens a capture to mark up again: its own session if it still has one, else the image itself, on the screen under the mouse.
    private func edit(_ shot: Shot) {
        if let s = shot.session { return open(s) }
        guard let screen = Self.screenUnderMouse, let id = screen.displayID else { return }
        let s = Library.flatSession(shot.cgImage, scale: shot.scale, displayID: id, fit: screen.frame.size)
        s.shotID = shot.id
        s.mode = shot.kind
        s.app = shot.app
        open(s)
    }

    func pin(_ shot: Shot) {
        guard let screen = shot.screen else { return }
        let k = min(1, 720 / shot.size.width, 520 / shot.size.height)
        let size = CGSize(width: shot.size.width * k, height: shot.size.height * k)
        weak var panel: NSPanel?
        let view = PinView(image: shot.image, size: size,
                           onClose: { [weak self] in if let panel { self?.close(panel) } },
                           onOpacity: { panel?.alphaValue = $0 })
        let p = makePanel(view)
        panel = p
        p.hasShadow = true
        p.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2))
        p.orderFrontRegardless()
    }

    private func makePanel(_ view: some View) -> NSPanel {
        let host = NSHostingView(rootView: view)
        let p = FloatingPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panels.append(p)
        return p
    }

    private func close(_ p: NSWindow) {
        p.orderOut(nil)
        panels.removeAll { $0 === p }
    }

    private func askForPermission() {
        // The first request shows the system prompt. After that macOS stays silent, so explain where the switch is.
        if UserDefaults.standard.bool(forKey: "askedForScreenRecording") {
            busy = true
            Self.explainPermission()
            busy = false
        } else {
            UserDefaults.standard.set(true, forKey: "askedForScreenRecording")
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private static func explainFailure(_ error: Error) {
        guard CGPreflightScreenCaptureAccess() else { return explainPermission() }
        let alert = NSAlert(error: error)
        alert.messageText = "Couldn't capture the screen"
        NSApp.activate()
        alert.runModal()
    }

    static func explainPermission() {
        let alert = NSAlert()
        alert.messageText = "Allow screen recording"
        alert.informativeText = "Shiny Screenshot needs Screen Recording permission to capture your screen. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openPrivacySettings() }
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

/// Cards and pins can take key status, so hover and their controls work while another app is active.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A finished capture: the rendered image plus, while it can still be edited, the session it came from.
struct Shot {
    let cgImage: CGImage
    let scale: CGFloat
    let displayID: CGDirectDisplayID
    /// No alpha to keep, so files are written as RGB.
    let opaque: Bool
    /// Nil for scrolling captures (taller than the overlay can show) and older Recent entries.
    private(set) var session: Session?
    private(set) var date = Date.now
    /// Shared by its copies and by every export of the same session, so the Library keeps a capture once.
    private(set) var id = UUID()
    var kind = CaptureMode.area
    /// The app in front when the capture started.
    var app: String?
    /// The background's name, when it had one.
    var backdrop: String?

    init?(_ s: Session) {
        guard let cg = s.render() else { return nil }
        self.init(cg, scale: s.pasteScale ?? s.scale, displayID: s.displayID, opaque: s.isOpaque)
        session = s
        id = s.shotID
        kind = s.mode
        app = s.app
        backdrop = s.style.enabled ? s.style.backdrop.name : nil
    }

    init(_ cgImage: CGImage, scale: CGFloat, displayID: CGDirectDisplayID, opaque: Bool = true) {
        self.cgImage = cgImage
        self.scale = scale
        self.displayID = displayID
        self.opaque = opaque
    }

    var screen: NSScreen? { NSScreen.screens.first { $0.displayID == displayID } }

    /// The same capture without its session, so it no longer holds a whole screen in memory.
    var withoutSession: Shot {
        var s = self
        s.session = nil
        return s
    }

    var caption: String {
        "\(Int(size.width)) × \(Int(size.height)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// For the Recent menu: at most 48 × 32 points, drawn when shown.
    var thumbnail: NSImage {
        let image = self.image
        let k = min(48 / size.width, 32 / size.height, 1)
        return NSImage(size: CGSize(width: size.width * k, height: size.height * k), flipped: false) { r in
            image.draw(in: r)
            return true
        }
    }

    var size: CGSize { CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale) }
    var image: NSImage { NSImage(cgImage: cgImage, size: size) }

    var png: Data? { Self.png(cgImage, size: size) }

    /// PNG tagged with the point size, so it pastes at the right size on Retina screens.
    /// Takes a second for a full 6K screen, so callers off the pasteboard run it in the background.
    /// `opaque` drops the alpha channel: files about 15% smaller, encoding about twice as slow, so only for files.
    nonisolated static func png(_ cgImage: CGImage, size: CGSize, opaque: Bool = false) -> Data? {
        let rep = NSBitmapImageRep(cgImage: opaque ? rgb(cgImage) ?? cgImage : cgImage)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }

    /// Puts the image on the pasteboard without encoding it; PNG or TIFF is made when another app pastes.
    func copy(to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        let provider = LazyImage(cgImage, size: size, on: pasteboard)
        item.setDataProvider(provider, forTypes: [.png, .tiff])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        provider.changeCount = pasteboard.changeCount
        LazyImage.current = provider
    }

    /// Where ⌘S saves, chosen in Settings.
    static var folder: URL { UserDefaults.standard.url(forKey: "saveFolder") ?? .desktopDirectory }
    static var folderName: String { FileManager.default.displayName(atPath: folder.path) }

    @discardableResult
    func save(to dir: URL = Shot.folder) -> URL? { Self.save(cgImage, size: size, opaque: opaque, to: dir) }

    /// Saves without blocking the UI.
    func saveInBackground(to dir: URL = Shot.folder) async -> URL? {
        let (cgImage, size, opaque) = (cgImage, size, opaque)
        return await Task.detached { Self.save(cgImage, size: size, opaque: opaque, to: dir) }.value
    }

    /// The image redrawn without an alpha channel.
    nonisolated static func rgb(_ image: CGImage) -> CGImage? {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx?.makeImage()
    }

    /// Writes a PNG named like macOS screenshots, adding " (2)", " (3)"… instead of overwriting.
    nonisolated static func save(_ cgImage: CGImage, size: CGSize, opaque: Bool = false, to dir: URL) -> URL? {
        guard let png = png(cgImage, size: size, opaque: opaque) else { return nil }
        let name = "Shiny Screenshot \(Self.timestamp.string(from: .now))"
        for n in 1...99 {
            let url = dir.appending(path: n == 1 ? "\(name).png" : "\(name) (\(n)).png")
            do {
                try png.write(to: url, options: .withoutOverwriting)
                return url
            } catch where (error as? CocoaError)?.code == .fileWriteFileExists {
                continue
            } catch {
                return nil
            }
        }
        return nil
    }

    /// DateFormatter is thread-safe for formatting.
    nonisolated(unsafe) private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    /// For dragging the card into other apps. The file is written in the background, only when an app takes the drop.
    func dragItem() -> NSItemProvider {
        let (cgImage, size, opaque) = (cgImage, size, opaque)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { done in
            Task.detached {
                Self.removeDragFiles(olderThan: 3600)
                let dir = Self.dragFolder.appending(path: UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    guard let url = Self.save(cgImage, size: size, opaque: opaque, to: dir) else { throw CocoaError(.fileWriteUnknown) }
                    done(url, false, nil)
                } catch {
                    done(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    /// Ours alone: the temporary folder is shared with other apps.
    nonisolated static let dragFolder = FileManager.default.temporaryDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "ShinyScreenshot").appending(path: "Drag")

    /// Drag files only need to outlive the drop, so the previous run's are cleared at launch.
    static func removeOldDragFiles() {
        try? FileManager.default.removeItem(at: dragFolder)
    }

    /// The app can run for weeks, so each new drag also clears ones older than `age` seconds.
    nonisolated static func removeDragFiles(olderThan age: TimeInterval) {
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: dragFolder, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let made = try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate, made < .now - age {
                try? fm.removeItem(at: dir)
            }
        }
    }
}

/// Supplies the pasteboard data on demand.
final class LazyImage: NSObject, NSPasteboardItemDataProvider {
    /// The pasteboard item doesn't keep its provider alive, so the latest copy is held here.
    static var current: LazyImage?

    /// Only the finished image: holding the Shot would keep its session, with two copies of the whole screen, alive.
    private let cgImage: CGImage
    private let size: CGSize
    private let pasteboard: NSPasteboard
    var changeCount = 0

    init(_ cgImage: CGImage, size: CGSize, on pasteboard: NSPasteboard) {
        self.cgImage = cgImage
        self.size = size
        self.pasteboard = pasteboard
    }

    private var png: Data? { Shot.png(cgImage, size: size) }
    private var tiff: Data? { NSImage(cgImage: cgImage, size: size).tiffRepresentation }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = type == .png ? png : tiff { item.setData(data, forType: type) }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        if Self.current === self { Self.current = nil }
    }

    /// Before quitting, swaps the promise for real data so the copy survives the app.
    func resolve() {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if let png { pasteboard.setData(png, forType: .png) }
        if let tiff { pasteboard.setData(tiff, forType: .tiff) }
    }
}
