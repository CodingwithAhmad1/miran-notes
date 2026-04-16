import KeyboardShortcuts

/// `KeyboardShortcuts` persists shortcuts in UserDefaults but also registers Carbon hotkeys that swallow key events
/// before SwiftUI menu shortcuts run. We only want menu-local key equivalents for workspace commands, so we
/// unregister the global monitors while keeping stored shortcuts for the recorder and ``getShortcut``.
enum WorkspaceShortcutCarbonPolicy {
    @MainActor
    static func suppressGlobalHotkeysForMenuShortcuts() {
        for command in WorkspaceShortcutCommand.allCases {
            KeyboardShortcuts.disable(command.keyboardShortcutName)
        }
    }
}
