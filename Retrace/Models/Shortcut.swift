import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key combination that works from any app, such as ⌥⇧⌘4.
nonisolated struct Shortcut: Codable, Hashable, Sendable {
    /// The hardware key code, so the shortcut stays on the same key across keyboard layouts.
    let keyCode: UInt32
    /// Raw `NSEvent.ModifierFlags`, limited to Command, Option, Control, and Shift.
    let modifiers: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    /// Builds a shortcut from a key press, or returns `nil` if it can't be a global shortcut.
    /// A global shortcut needs Command, Option, or Control, unless it's a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevantModifiers)
        let keyCode = UInt32(event.keyCode)
        let hasCommandKey = !flags.intersection([.command, .option, .control]).isEmpty
        guard hasCommandKey || Self.functionKeys.contains(Int(keyCode)) else { return nil }
        self.init(keyCode: keyCode, modifiers: flags)
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// The modifiers in the form Carbon's hot key API expects.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// The shortcut as macOS writes it in menus, such as "⌥⇧⌘4".
    var displayString: String {
        var text = ""
        if modifierFlags.contains(.control) { text += "⌃" }
        if modifierFlags.contains(.option) { text += "⌥" }
        if modifierFlags.contains(.shift) { text += "⇧" }
        if modifierFlags.contains(.command) { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// The menu key equivalent, when the key types a character.
    var keyEquivalent: KeyEquivalent? {
        if let special = Self.specialKeyEquivalents[Int(keyCode)] { return special }
        let name = Self.keyName(for: keyCode)
        guard name.count == 1, let character = name.lowercased().first else { return nil }
        return KeyEquivalent(character)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifierFlags.contains(.command) { result.insert(.command) }
        if modifierFlags.contains(.option) { result.insert(.option) }
        if modifierFlags.contains(.control) { result.insert(.control) }
        if modifierFlags.contains(.shift) { result.insert(.shift) }
        return result
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeyEquivalents: [Int: KeyEquivalent] = [
        kVK_Return: .return, kVK_Tab: .tab, kVK_Space: .space, kVK_Delete: .delete,
        kVK_ForwardDelete: .deleteForward, kVK_Escape: .escape, kVK_LeftArrow: .leftArrow,
        kVK_RightArrow: .rightArrow, kVK_UpArrow: .upArrow, kVK_DownArrow: .downArrow,
        kVK_Home: .home, kVK_End: .end, kVK_PageUp: .pageUp, kVK_PageDown: .pageDown,
    ]

    /// The key's label on the current keyboard layout, such as "4" or "A".
    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

extension View {
    /// Shows a global shortcut next to a menu item.
    @ViewBuilder
    func menuShortcut(_ shortcut: Shortcut?) -> some View {
        if let shortcut, let key = shortcut.keyEquivalent {
            keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}
