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
    @AppStorage("shortcut") private var shortcut = Shortcut.standard

    var body: some View {
        if let version = Updates.shared.available {
            Button("Update to \(version)…") { Updates.shared.check() }
            Divider()
        }
        Button("Capture Area") { Shiny.shared.capture() }
            .keyboardShortcut(shortcut.menuShortcut)
        Button("Capture Full Screen") { Shiny.shared.capture(fullScreen: true) }
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
        if !Shiny.shared.registerShortcut() {
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

enum OverlayAction { case copy, save, pin, cancel }

/// Owns the capture overlay and the floating cards and pins it leaves behind.
final class Shiny {
    static let shared = Shiny()

    private var overlay: NSWindow?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var panels: [NSWindow] = []
    private var settings: NSWindow?
    private var hotkey: Hotkey?
    /// From the hotkey until the overlay closes (or an alert is dismissed), so a second press can't start a second capture.
    private var busy = false

    func capture(fullScreen: Bool = false) {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else { return askForPermission() }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let id = screen.displayID else { return }
        let scale = screen.backingScaleFactor
        busy = true
        Task {
            do {
                let session = Session(try await Capture.freeze(displayID: id, scale: scale), displayID: id)
                if fullScreen { session.selectAll() }
                busy = false
                open(session)
            } catch {
                Self.explainFailure(error)
                busy = false
            }
        }
    }

    /// Registers the saved shortcut (⇧⌘2 by default: free on macOS, unlike ⇧⌘3/4/5). False when another app owns it.
    @discardableResult
    func registerShortcut() -> Bool {
        hotkey?.unregister()
        let s = Shortcut.saved
        hotkey = Hotkey(keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in self?.capture() }
        return shortcutRegistered
    }

    func unregisterShortcut() {
        hotkey?.unregister()
    }

    var shortcutRegistered: Bool { hotkey?.isRegistered ?? false }

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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event, s) ?? event
        }
        // Clicking another app (say, on a second display) takes the keyboard away: cancel instead of leaving Esc dead.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeOverlay() }
        }
    }

    private func closeOverlay() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        resignObserver = nil
        keyMonitor = nil
        overlay?.orderOut(nil)
        overlay = nil
        busy = false
    }

    /// Returns nil when the key was handled.
    private func handleKey(_ e: NSEvent, _ s: Session) -> NSEvent? {
        if s.editingText != nil {
            // Keys belong to the label being typed, unless its field never got focus.
            if overlay?.firstResponder is NSText { return e }
            s.commitText()
        }
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd, Self.letter(e)) {
        case (UInt16(kVK_Escape), _, _):
            if s.tool != nil { s.tool = nil } else if s.style.enabled { s.style.enabled = false } else { closeOverlay() }
        case (UInt16(kVK_Return), _, _), (UInt16(kVK_ANSI_KeypadEnter), _, _), (_, true, "c"):
            handle(.copy, s)
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
        guard !s.selection.isEmpty, let shot = Shot(s) else { return }
        closeOverlay()
        switch action {
        case .copy: shot.copy(); showCard(shot, title: "Copied to clipboard")
        case .save: showSaved(shot)
        case .pin: pin(shot)
        case .cancel: break
        }
    }

    private func showSaved(_ shot: Shot) {
        Task {
            let saved = await shot.saveInBackground() != nil
            showCard(shot, title: saved ? "Saved to \(Shot.folderName)" : "Couldn't save to \(Shot.folderName)")
        }
    }

    private func showCard(_ shot: Shot, title: String) {
        guard let screen = shot.session.screen else { return }
        // Weak: the panel's view holds this closure, and `panels` keeps the panel alive while it is shown.
        weak var panel: NSPanel?
        let card = CardView(title: title, image: shot.image, drag: shot.dragItem) { [weak self] action in
            guard let self, let panel else { return }
            self.close(panel)
            switch action {
            case .copy: shot.copy()
            case .save: self.showSaved(shot)
            case .pin: self.pin(shot)
            case .edit: self.open(shot.session)
            case .dismiss: break
            }
        }
        let p = makePanel(card)
        panel = p
        p.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY))
        p.orderFrontRegardless()
    }

    private func pin(_ shot: Shot) {
        guard let screen = shot.session.screen else { return }
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

/// A finished capture: the rendered image plus the session, so it can be edited again.
struct Shot {
    let cgImage: CGImage
    let session: Session

    init?(_ s: Session) {
        guard let cg = s.render() else { return nil }
        cgImage = cg
        session = s
    }

    var size: CGSize { CGSize(width: CGFloat(cgImage.width) / session.scale, height: CGFloat(cgImage.height) / session.scale) }
    var image: NSImage { NSImage(cgImage: cgImage, size: size) }

    var png: Data? { Self.png(cgImage, size: size) }

    /// PNG tagged with the point size, so it pastes at the right size on Retina screens.
    /// Takes a second for a full 6K screen, so callers off the pasteboard run it in the background.
    nonisolated static func png(_ cgImage: CGImage, size: CGSize) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
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
    func save(to dir: URL = Shot.folder) -> URL? { Self.save(cgImage, size: size, to: dir) }

    /// Saves without blocking the UI.
    func saveInBackground(to dir: URL = Shot.folder) async -> URL? {
        let (cgImage, size) = (cgImage, size)
        return await Task.detached { Self.save(cgImage, size: size, to: dir) }.value
    }

    /// Writes a PNG named like macOS screenshots, adding " (2)", " (3)"… instead of overwriting.
    nonisolated static func save(_ cgImage: CGImage, size: CGSize, to dir: URL) -> URL? {
        guard let png = png(cgImage, size: size) else { return nil }
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
        let (cgImage, size) = (cgImage, size)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { done in
            Task.detached {
                Self.removeDragFiles(olderThan: 3600)
                let dir = Self.dragFolder.appending(path: UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    guard let url = Self.save(cgImage, size: size, to: dir) else { throw CocoaError(.fileWriteUnknown) }
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
