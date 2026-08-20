import KeyboardShortcuts
import SwiftUI

/// Shortcut recorders for New Folder / New Note, plus restore. Shown in the Settings window Shortcuts tab.
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

/// The system Settings window (⌘,): General (vault), Editor (feature toggles), Shortcuts.
struct MiranNotesSettingsView: View {
    @Bindable var settings: AppSettings
    /// Path of the currently open vault; nil before a vault is chosen.
    var vaultRootPath: String?
    var onSwitchVault: () -> Void = {}
    var onWorkspaceShortcutsChanged: () -> Void = {}

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape")
                }
            editorTab
                .tabItem {
                    Label(String(localized: "Editor", comment: "Settings tab"), systemImage: "text.cursor")
                }
            shortcutsTab
                .tabItem {
                    Label(String(localized: "Shortcuts", comment: "Settings tab"), systemImage: "keyboard")
                }
        }
        .frame(minWidth: 480, minHeight: 280)
    }

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Vault", comment: "Settings: current vault row label")) {
                    Text(vaultRootPath ?? String(localized: "No vault open", comment: "Settings: shown when no vault is open"))
                        .foregroundStyle(vaultRootPath == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button(String(localized: "Switch Vault…", comment: "Settings: open a different vault")) {
                    onSwitchVault()
                }
            } header: {
                Text("Vault", comment: "Settings: vault section header")
            }

            Section {
                Toggle(
                    String(localized: "Reopen last vault at launch", comment: "Settings: bookmark restore toggle"),
                    isOn: $settings.reopenLastVaultAtLaunch
                )
            } footer: {
                Text(
                    "When off, Miran Notes asks you to pick a vault folder every time it starts.",
                    comment: "Settings: bookmark restore toggle explanation"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var editorTab: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Clickable note links", comment: "Settings: wiki-link styling and navigation toggle"),
                    isOn: $settings.wikiLinkNavigationEnabled
                )
                Toggle(
                    String(localized: "Suggest notes when typing [[", comment: "Settings: wiki-link autocomplete toggle"),
                    isOn: $settings.wikiLinkAutocompleteEnabled
                )
            } header: {
                Text("Note links", comment: "Settings: editor links section header")
            }

            Section {
                LabeledContent(String(localized: "Text size", comment: "Settings: editor font size")) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.editorBodyPointSize, in: 12...20, step: 1)
                            .frame(width: 160)
                        Text("\(Int(settings.editorBodyPointSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Appearance", comment: "Settings: editor appearance section header")
            } footer: {
                Text(
                    "Headings and code scale with the body size.",
                    comment: "Settings: font size explanation"
                )
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    String(localized: "Roll over unfinished tasks each day", comment: "Settings: tasks auto-rollover toggle"),
                    isOn: $settings.autoRollOverTasks
                )
            } header: {
                Text("Today’s Tasks", comment: "Settings: tasks section header")
            } footer: {
                Text(
                    "When a new day starts with no tasks, unfinished tasks from the last active day are copied in.",
                    comment: "Settings: auto-rollover explanation"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            WorkspaceKeyboardShortcutsSettingsSections(
                sectionHeader: Text("Workspace", comment: "Settings: keyboard shortcuts section header"),
                onWorkspaceShortcutsChanged: onWorkspaceShortcutsChanged
            )
        }
        .formStyle(.grouped)
    }
}
