import AppKit
import KeyboardShortcuts
import SwiftUI

/// Stable identifiers for workspace actions that may be rebound in Folder Management (toolbar gear).
enum WorkspaceShortcutCommand: String, CaseIterable, Sendable {
    case newFolder
    case newNote

    var keyboardShortcutName: KeyboardShortcuts.Name {
        switch self {
        case .newFolder: .workspaceNewFolder
        case .newNote: .workspaceNewNote
        }
    }

    /// Label beside the shortcut recorder in Folder Management.
    var settingsRecorderLabel: String {
        switch self {
        case .newFolder:
            String(localized: "New Folder", comment: "Settings: shortcut row title")
        case .newNote:
            String(localized: "New Note", comment: "Settings: shortcut row title")
        }
    }
}

@MainActor
enum WorkspaceMenuKeyboardShortcutResolver {
    /// Maps a stored shortcut to SwiftUI’s menu style. Mirrors ``KeyboardShortcuts.Shortcut/toSwiftUI`` (internal in the package) using public APIs.
    static func swiftUIKeyboardShortcut(for command: WorkspaceShortcutCommand) -> KeyboardShortcut? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: command.keyboardShortcutName) else { return nil }
        return swiftUIKeyboardShortcut(from: shortcut)
    }

    private static func swiftUIKeyboardShortcut(from shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcut? {
        guard let keyEq = shortcut.nsMenuItemKeyEquivalent, keyEq.count == 1, let character = keyEq.first else {
            return nil
        }
        let modifiers = eventModifiers(from: shortcut.modifiers)
        if #available(macOS 12.0, *) {
            return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers, localization: .custom)
        }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    private static func eventModifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers = EventModifiers()
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.numericPad) { modifiers.insert(.numericPad) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) {
            modifiers.insert(EventModifiers(rawValue: 64))
        }
        return modifiers
    }
}

extension View {
    @ViewBuilder
    func workspaceMenuKeyboardShortcut(_ command: WorkspaceShortcutCommand) -> some View {
        if let shortcut = WorkspaceMenuKeyboardShortcutResolver.swiftUIKeyboardShortcut(for: command) {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
