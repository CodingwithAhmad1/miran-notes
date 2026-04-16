import KeyboardShortcuts
import SwiftUI

struct MiranNotesSettingsView: View {
    /// Bump a counter in the `App` so menu key equivalents re-resolve after edits.
    var onWorkspaceShortcutsChanged: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(WorkspaceShortcutCommand.allCases, id: \.self) { command in
                        KeyboardShortcuts.Recorder(
                            command.settingsRecorderLabel,
                            name: command.keyboardShortcutName,
                            onChange: { _ in
                                onWorkspaceShortcutsChanged()
                            }
                        )
                    }
                } header: {
                    Text("Workspace", comment: "Settings: keyboard shortcuts section")
                }

                Section {
                    Button(String(localized: "Restore Default Shortcuts", comment: "Settings: reset keyboard shortcuts")) {
                        restoreWorkspaceShortcutDefaults()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Settings", comment: "Settings window title"))
        }
        .frame(minWidth: 520, minHeight: 280)
    }

    private func restoreWorkspaceShortcutDefaults() {
        for command in WorkspaceShortcutCommand.allCases {
            let name = command.keyboardShortcutName
            KeyboardShortcuts.setShortcut(name.defaultShortcut, for: name)
        }
        onWorkspaceShortcutsChanged()
    }
}
