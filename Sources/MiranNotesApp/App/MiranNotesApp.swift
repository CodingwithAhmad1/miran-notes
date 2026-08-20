import AppKit
import KeyboardShortcuts
import MiranNotesCore
import SwiftUI

private final class MiranNotesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
    }
}

@main
struct MiranNotesApp: App {
    @NSApplicationDelegateAdaptor(MiranNotesAppDelegate.self) private var appDelegate
    @State private var vaultAccess: VaultWorkspaceAccess?
    @State private var model: AppModel?
    @State private var sessionRegistry = VaultSessionRegistry()
    @State private var settings = AppSettings.shared
    @State private var conflictDetailsPresented = false
    @State private var conflictDetailsDiskDate: Date?
    @State private var editingHelpPresented = false
    @State private var vaultPickerErrorMessage: String?
    /// Picker chose a folder that failed the compatibility gate; full report (same UI as runtime gate).
    @State private var incompatiblePick: (report: CompatibilityReport, vaultURL: URL)?
    /// Forces ``appCommands`` to re-read shortcuts from `KeyboardShortcuts` / UserDefaults.
    @State private var menuShortcutEpoch = 0

    init() {
        SlashCommandRegistry.registerBuiltins()
        if ProcessInfo.processInfo.environment["MIRAN_USE_DEFAULT_VAULT"] == "1" {
            let devVault = Self.defaultVaultDirectoryURL()
            try? FileManager.default.createDirectory(at: devVault, withIntermediateDirectories: true)
        }
        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: Self.bootstrapDefaultVaultURL())
        switch outcome {
        case .resolved(let access):
            _vaultAccess = State(initialValue: access)
            _model = State(initialValue: AppModel(repository: NoteRepository(vaultURL: access.vaultRootURL)))
        case .needsUserSelectedVault:
            _vaultAccess = State(initialValue: nil)
            _model = State(initialValue: nil)
        }

        Self.seedWorkspaceShortcutDefaultsAndUseMenuOnlyHotkeys()
    }

    /// Ensures `KeyboardShortcuts` UserDefaults entries exist and disables Carbon hotkeys so File menu shortcuts still fire.
    private static func seedWorkspaceShortcutDefaultsAndUseMenuOnlyHotkeys() {
        for command in WorkspaceShortcutCommand.allCases {
            _ = command.keyboardShortcutName
        }
        WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
    }

    /// When `MIRAN_USE_DEFAULT_VAULT=1` is set, restores the legacy `~/MiranNotesVault` bootstrap for local iteration without picking a folder.
    private static func bootstrapDefaultVaultURL() -> URL? {
        if ProcessInfo.processInfo.environment["MIRAN_USE_DEFAULT_VAULT"] == "1" {
            return defaultVaultDirectoryURL()
        }
        return nil
    }

    private static func defaultVaultDirectoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("MiranNotesVault", isDirectory: true)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let model {
                        MiranNotesMainWindowContent(
                            model: model,
                            presentOpenWorkspacePanel: presentOpenWorkspacePanel,
                            conflictDetailsPresented: $conflictDetailsPresented,
                            conflictDetailsDiskDate: $conflictDetailsDiskDate,
                            editingHelpPresented: $editingHelpPresented,
                            onWorkspaceShortcutsChanged: {
                                menuShortcutEpoch &+= 1
                                WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
                            }
                        )
                    } else {
                        VaultWelcomeView(onOpenVault: presentOpenWorkspacePanel)
                            .alert(
                                "Error",
                                isPresented: Binding(
                                    get: { vaultPickerErrorMessage != nil },
                                    set: { if !$0 { vaultPickerErrorMessage = nil } }
                                )
                            ) {
                                Button("OK", role: .cancel) {
                                    vaultPickerErrorMessage = nil
                                }
                            } message: {
                                Text(vaultPickerErrorMessage ?? "")
                            }
                    }
                }
                if let model {
                    QuickOpenPaletteView(model: model)
                }
                if let pick = incompatiblePick {
                    WorkspaceIncompatibleView(
                        report: pick.report,
                        vaultRootURL: pick.vaultURL,
                        onChooseDifferentFolder: {
                            incompatiblePick = nil
                            presentOpenWorkspacePanel()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .environment(sessionRegistry)
            .environment(settings)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { appCommands }

        Settings {
            MiranNotesSettingsView(
                settings: settings,
                vaultRootPath: vaultAccess?.vaultRootURL.path,
                onSwitchVault: presentOpenWorkspacePanel,
                onWorkspaceShortcutsChanged: {
                    menuShortcutEpoch &+= 1
                    WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
                }
            )
            .environment(settings)
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        let _ = menuShortcutEpoch
        CommandGroup(after: .newItem) {
            Button("Switch Vault…") {
                presentOpenWorkspacePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("New Folder") {
                model?.performNewFolderFromShortcut()
            }
            .workspaceMenuKeyboardShortcut(.newFolder)
            Button("New Note") {
                model?.performNewNoteFromShortcut()
            }
            .workspaceMenuKeyboardShortcut(.newNote)
            Button("Quick Open…") {
                model?.quickOpen.toggle()
            }
            .keyboardShortcut("p", modifiers: .command)
        }
        CommandGroup(replacing: .importExport) {
            Button("Attach File…") {
                model?.presentAttachFilePanel()
            }
            .disabled(model?.activeDocument == nil)
            Divider()
            Button("Export as Markdown…") {
                model?.presentExportPanel(kind: .markdown)
            }
            .disabled(model?.activeDocument == nil)
            Button("Export as PDF…") {
                model?.presentExportPanel(kind: .pdf)
            }
            .disabled(model?.activeDocument == nil)
        }
        CommandGroup(after: .help) {
            Button("Editing in Miran Notes…") {
                editingHelpPresented = true
            }
        }
        CommandMenu("Format") {
            Button("Bold") {
                NSApp.sendAction(Selector(("toggleBold:")), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("Italic") {
                NSApp.sendAction(Selector(("toggleItalic:")), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("Code") {
                NSApp.sendAction(Selector(("toggleCodeSpan:")), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    private func presentOpenWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktop
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let newAccess = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(url)
            incompatiblePick = nil
            vaultAccess?.stopAccessingIfNeeded()
            vaultAccess = newAccess
            model = AppModel(repository: NoteRepository(vaultURL: newAccess.vaultRootURL))
            model?.loadVault()
        } catch let adoption as VaultWorkspaceAdoptionError {
            switch adoption {
            case .incompatibleVault(let report):
                incompatiblePick = (report, url.standardizedFileURL)
            }
        } catch {
            let message =
                "Could not remember access to the folder you chose. Try again or check disk permissions."
            if let model {
                model.userAlert = .message("\(message) \(error.localizedDescription)")
            } else {
                vaultPickerErrorMessage = "\(message) \(error.localizedDescription)"
            }
        }
    }

}
