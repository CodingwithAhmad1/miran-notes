import KeyboardShortcuts
import SwiftUI

/// Shortcut recorders for New Folder / New Note, plus restore. Shown in Folder Management below the folder list.
struct WorkspaceKeyboardShortcutsSettingsSections: View {
    var sectionHeader: Text
    /// Bump a counter in the `App` so menu key equivalents re-resolve after edits.
    var onWorkspaceShortcutsChanged: () -> Void = {}

    var body: some View {
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
            sectionHeader
        }

        Section {
            Button(String(localized: "Restore Default Shortcuts", comment: "Settings: reset keyboard shortcuts")) {
                restoreWorkspaceShortcutDefaults()
            }
        }
    }

    private func restoreWorkspaceShortcutDefaults() {
        for command in WorkspaceShortcutCommand.allCases {
            let name = command.keyboardShortcutName
            KeyboardShortcuts.setShortcut(name.defaultShortcut, for: name)
        }
        onWorkspaceShortcutsChanged()
    }
}

/// Placeholder for the system Settings window (⌘,). Workspace shortcuts are configured in Folder Management.
struct MiranNotesSettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(String(localized: "Miran Notes", comment: "Settings window: app name in empty state"), systemImage: "note.text")
            } description: {
                Text(
                    "Workspace keyboard shortcuts are set in Folder Management: choose the toolbar gear, then the Keyboard shortcuts section below your folders.",
                    comment: "Settings window: directs user to folder management for shortcuts"
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            }
            .navigationTitle(Text("Settings", comment: "Settings window title"))
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
