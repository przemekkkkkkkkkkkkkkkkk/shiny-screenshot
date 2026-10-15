import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ShinyScreenshot

/// Recording a capture shortcut from key events, and storing it in UserDefaults.
struct ShortcutTests {
    func key(_ code: Int, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }

    @Test func standardIsShiftCommand2() {
        #expect(Shortcut.standard.display == "⇧⌘2")
        #expect(Shortcut.standard.menuShortcut == KeyboardShortcut("2", modifiers: [.shift, .command]))
    }

    @Test func recordsModifiersInDisplayOrder() throws {
        let s = try #require(Shortcut(key(kVK_ANSI_X, "x", [.command, .option, .control])))
        #expect(s.modifiers == UInt32(cmdKey | optionKey | controlKey))
        #expect(s.display == "⌃⌥⌘X")
    }

    @Test func refusesShortcutsThatWouldSwallowTyping() {
        #expect(Shortcut(key(kVK_ANSI_X, "x", [])) == nil)
        #expect(Shortcut(key(kVK_ANSI_X, "X", [.shift])) == nil)
    }

    @Test func refusesStandardCommandShortcuts() throws {
        #expect(Shortcut(key(kVK_ANSI_C, "c", [.command])) == nil)
        #expect(Shortcut(key(kVK_ANSI_Q, "q", [.command])) == nil)
        #expect(Shortcut(key(kVK_Space, " ", [.command])) == nil)
        _ = try #require(Shortcut(key(kVK_ANSI_4, "4", [.command, .shift])))
        _ = try #require(Shortcut(key(kVK_F5, "\u{10}", [.command, .function])))
    }

    @Test func functionKeysNeedNoModifier() throws {
        let s = try #require(Shortcut(key(kVK_F5, "\u{10}", [.function])))
        #expect(s.display == "F5")
        #expect(s.modifiers == 0)
        #expect(s.menuShortcut?.key == KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)))
    }

    @Test func survivesStorageIncludingSpace() {
        let space = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: " ")
        #expect(Shortcut(rawValue: space.rawValue) == space)
        #expect(space.display == "⌥Space")
        #expect(Shortcut(rawValue: "garbage") == nil)
    }
}
