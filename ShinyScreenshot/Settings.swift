import Carbon.HIToolbox
import ServiceManagement
import Sparkle
import SwiftUI

/// The global capture shortcut: Carbon key code and modifiers, plus the key as typed without modifiers.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), key: "2")
    static var saved: Shortcut { UserDefaults.standard.string(forKey: "shortcut").flatMap(Shortcut.init) ?? .standard }

    private static let flags: [(carbon: Int, symbol: String, swiftUI: SwiftUI.EventModifiers)] = [
        (controlKey, "⌃", .control), (optionKey, "⌥", .option), (shiftKey, "⇧", .shift), (cmdKey, "⌘", .command),
    ]

    private static let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

    /// Keys with no printable character: their name, and the character AppKit menus use for them.
    private static let special: [Int: (name: String, char: Int)] = {
        var d = [kVK_Space: ("Space", 0x20), kVK_LeftArrow: ("←", NSLeftArrowFunctionKey), kVK_RightArrow: ("→", NSRightArrowFunctionKey),
                 kVK_UpArrow: ("↑", NSUpArrowFunctionKey), kVK_DownArrow: ("↓", NSDownArrowFunctionKey)]
        for (i, code) in fKeys.enumerated() { d[code] = ("F\(i + 1)", NSF1FunctionKey + i) }
        return d
    }()

    var display: String {
        Self.flags.filter { modifiers & UInt32($0.carbon) != 0 }.map(\.symbol).joined()
            + (Self.special[Int(keyCode)]?.name ?? key.uppercased())
    }

    /// Shown next to the menu item.
    var menuShortcut: KeyboardShortcut? {
        guard let c = key.first, key.count == 1 else { return nil }
        let m = Self.flags.filter { modifiers & UInt32($0.carbon) != 0 }.map(\.swiftUI)
        return KeyboardShortcut(KeyEquivalent(c), modifiers: SwiftUI.EventModifiers(m))
    }
}

extension Shortcut: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt32(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(keyCode: code, modifiers: mods, key: String(parts[2]))
    }

    var rawValue: String { "\(keyCode) \(modifiers) \(key)" }

    /// The shortcut typed in `e`, or nil when it would swallow ordinary typing or a standard command like ⌘C or ⌘Q:
    /// it needs ⌃ or ⌥, or ⌘ with another modifier, unless it's a function key.
    init?(_ e: NSEvent) {
        let code = Int(e.keyCode)
        let special = Self.special[code].flatMap { UnicodeScalar($0.char) }.map { String($0) }
        guard let key = special ?? e.characters(byApplyingModifiers: []), !key.isEmpty else { return nil }
        let flags = e.modifierFlags
        guard Self.fKeys.contains(code) || !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let pairs: [(NSEvent.ModifierFlags, Int)] = [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        let mods = pairs.filter { flags.contains($0.0) }.reduce(0) { $0 | $1.1 }
        guard Self.fKeys.contains(code) || mods != cmdKey else { return nil }
        self.init(keyCode: UInt32(code), modifiers: UInt32(mods), key: key)
    }
}

/// Sparkle, plus whether a scheduled check found an update the menu should mention.
@Observable
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    /// Version found by a background check, until the user looks at it.
    private(set) var available: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func check() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // A menu bar app has no window of its own, so an alert from a background check would pop up behind other apps.
    // Sparkle shows it only right after launch; otherwise the menu offers the update.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { NSApp.activate() } else { available = update.displayVersionString }
    }

    func standardUserDriverWillFinishUpdateSession() {
        available = nil
    }
}

struct SettingsView: View {
    @AppStorage("shortcut") private var shortcut = Shortcut.standard
    @AppStorage("saveFolder") private var folder = URL.desktopDirectory
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var autoCheck = Updates.shared.updater.automaticallyChecksForUpdates
    @State private var autoInstall = Updates.shared.updater.automaticallyDownloadsUpdates
    private let canRecord = CGPreflightScreenCaptureAccess()
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shiny Screenshot").font(.title3.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Capture") {
                LabeledContent("Shortcut") { ShortcutRecorder(shortcut: $shortcut) }
                LabeledContent {
                    Button("Choose…", action: chooseFolder)
                } label: {
                    Text("Save to")
                    Label(FileManager.default.displayName(atPath: folder.path), systemImage: "folder")
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                LabeledContent {
                    if canRecord {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { Shiny.openPrivacySettings() }
                    }
                } label: {
                    Text("Screen Recording")
                    if !canRecord { Text("Needed to capture. Reopen the app after turning it on.") }
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoCheck)
                    .onChange(of: autoCheck) { Updates.shared.updater.automaticallyChecksForUpdates = $1 }
                Toggle("Download and install updates automatically", isOn: $autoInstall)
                    .onChange(of: autoInstall) { Updates.shared.updater.automaticallyDownloadsUpdates = $1 }
                    .disabled(!autoCheck)
                LabeledContent {
                    Button("Check Now") { Updates.shared.check() }
                } label: {
                    Text("Software update")
                    Text(Updates.shared.updater.lastUpdateCheckDate.map {
                        "Last checked \($0.formatted(.relative(presentation: .named)))"
                    } ?? "Not checked yet")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }

    private func setOpenAtLogin(_ on: Bool) {
        let app = SMAppService.mainApp
        try? on ? app.register() : app.unregister()
        if app.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        openAtLogin = app.status == .enabled
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }
}

/// Click, then type the new shortcut. Esc cancels.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var monitor: Any?
    @State private var taken = !Shiny.shared.shortcutRegistered

    var body: some View {
        HStack(spacing: 8) {
            if taken && monitor == nil {
                Label("Used by another app", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            Button(monitor == nil ? shortcut.display : "Type shortcut…") { monitor == nil ? start() : stop() }
                .frame(minWidth: 110)
                .help("Click, then press the keys you want")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        // Off while recording, so pressing the current shortcut records it instead of starting a capture.
        Shiny.shared.unregisterShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let s = Shortcut(e) {
                shortcut = s
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        taken = !Shiny.shared.registerShortcut()
    }
}
