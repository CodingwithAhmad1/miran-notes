import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let workspaceNewFolder = Self(
        "workspaceNewFolder",
        default: KeyboardShortcuts.Shortcut(.d, modifiers: .command)
    )
    static let workspaceNewNote = Self(
        "workspaceNewNote",
        default: KeyboardShortcuts.Shortcut(.t, modifiers: .command)
    )
}
