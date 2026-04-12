import Foundation
import MiranNotesCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var noteSummaries: [NoteSummary] = []
    @Published var selectedBaseName: String?
    @Published var activeDocument: NoteDocument?
    @Published var isLoading = false
    @Published var lastError: String?
    /// Shown when the vault file on disk differs from the buffer while there are unsaved local edits.
    @Published var externalEditConflict = false

    private let repository: NoteRepository
    private var saveTask: Task<Void, Never>?
    private var vaultWatcher: VaultDirectoryWatcher?
    /// Set when the vault watcher fires; processed after autosave finishes so events are not dropped.
    private var pendingExternalDiskCheck = false
    /// Last snapshot known to match on-disk files (after load or successful save). Used with `activeDocument` to detect dirty state.
    private var lastPersistedDocument: NoteDocument?
    private var lastKnownDiskDate: Date?
    private var pendingConflictDiskDate: Date?
    private var undoManager: UndoManager?

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func setUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    func loadVault() {
        Task {
            await refreshNotes()
            if selectedBaseName == nil {
                selectedBaseName = noteSummaries.first?.baseName
            }
            await loadSelectedNote()
            startVaultWatcher()
        }
    }

    func refreshNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            noteSummaries = try await repository.listNotes()
        } catch {
            lastError = "Failed to list notes: \(error.localizedDescription)"
        }
    }

    func createNote() {
        Task {
            do {
                let (document, baseName) = try await repository.createNote(named: "untitled-note")
                await refreshNotes()
                selectedBaseName = baseName
                activeDocument = document
                lastPersistedDocument = document
                do {
                    lastKnownDiskDate = try await repository.noteModifiedDate(baseName: baseName)
                } catch {
                    lastError = "Failed to read note timestamps: \(error.localizedDescription)"
                }
                clearUndoStack()
            } catch {
                lastError = "Failed to create note: \(error.localizedDescription)"
            }
        }
    }

    func loadSelectedNote() async {
        guard let selectedBaseName else {
            activeDocument = nil
            lastPersistedDocument = nil
            lastKnownDiskDate = nil
            clearUndoStack()
            return
        }
        do {
            let loaded = try await repository.loadNote(baseName: selectedBaseName)
            activeDocument = loaded
            lastPersistedDocument = loaded
            do {
                lastKnownDiskDate = try await repository.noteModifiedDate(baseName: selectedBaseName)
            } catch {
                lastError = "Failed to read note timestamps: \(error.localizedDescription)"
            }
            clearUndoStack()
        } catch {
            lastError = "Failed to load note: \(error.localizedDescription)"
        }
    }

    func apply(_ command: EditCommand) {
        apply([command])
    }

    func apply(_ commands: [EditCommand], recordUndo: Bool = true) {
        guard var doc = activeDocument else { return }
        let before = doc
        for command in commands {
            doc = EditCommandEngine.apply(command, to: doc)
        }
        guard doc != before else { return }

        if recordUndo, let undo = undoManager {
            let after = doc
            undo.registerUndo(withTarget: self) { model in
                model.applyUndoSnapshot(from: after, to: before)
            }
            undo.setActionName(Self.undoActionName(for: commands))
        }

        activeDocument = doc
        scheduleAutosave()
    }

    private func applyUndoSnapshot(from after: NoteDocument, to before: NoteDocument) {
        activeDocument = before
        scheduleAutosave()
        undoManager?.registerUndo(withTarget: self) { model in
            model.applyUndoSnapshot(from: before, to: after)
        }
    }

    private func clearUndoStack() {
        undoManager?.removeAllActions(withTarget: self)
    }

    private static func undoActionName(for commands: [EditCommand]) -> String {
        if commands.count >= 2 {
            let head = Array(commands.prefix(2))
            if head.count == 2 {
                switch (head[0], head[1]) {
                case let (.replaceText(range, replacement), .splitBlock):
                    if range.length == 0, replacement == "\n" {
                        return "Split Block"
                    }
                case (.mergeWithPrevious, .replaceText):
                    return "Merge Blocks"
                default:
                    break
                }
            }
        }

        let kinds = Set(commands.map { command -> String in
            switch command {
            case .replaceText: return "Edit"
            case .splitBlock: return "Split Block"
            case .mergeWithPrevious: return "Merge Blocks"
            case .changeBlockType: return "Change Block"
            case .toggleSpanStyle: return "Toggle Style"
            case .repairMetadata: return "Repair Note"
            }
        })
        if kinds.count == 1, let only = kinds.first {
            return only
        }
        return "Edit"
    }

    func changeSelection(baseName: String?) {
        externalEditConflict = false
        pendingConflictDiskDate = nil
        selectedBaseName = baseName
        Task {
            await loadSelectedNote()
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        guard let note = activeDocument, let baseName = selectedBaseName else { return }
        saveTask = Task {
            defer {
                Task { @MainActor in
                    self.saveTask = nil
                    await self.runPendingExternalDiskReconciliationIfNeeded()
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try await repository.save(note, asBaseName: baseName)
                let modified = try await repository.noteModifiedDate(baseName: baseName)
                await MainActor.run {
                    self.lastKnownDiskDate = modified
                    // Persist authority matches the bytes written (`note`), not a possibly newer `activeDocument`.
                    self.lastPersistedDocument = note
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Autosave failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func reloadFromDisk() {
        Task {
            await loadSelectedNote()
        }
    }

    /// Dismisses the conflict alert. If `reloadFromDisk` is true, loads the note from the vault (discarding local edits). Otherwise keeps the buffer and records the external file time so the same change does not re-alert until the file changes again.
    func resolveExternalEditConflict(reloadFromDisk: Bool) {
        externalEditConflict = false
        let diskDate = pendingConflictDiskDate
        pendingConflictDiskDate = nil
        if reloadFromDisk {
            Task {
                await loadSelectedNote()
            }
        } else if let diskDate {
            lastKnownDiskDate = diskDate
        }
    }

    private func startVaultWatcher() {
        vaultWatcher?.cancel()
        vaultWatcher = VaultDirectoryWatcher(
            vaultURL: repository.vaultURL,
            onSetupFailed: { [weak self] error in
                self?.lastError = "Vault watch failed: \(error.localizedDescription)"
            },
            onEvent: { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.pendingExternalDiskCheck = true
                    await self?.runPendingExternalDiskReconciliationIfNeeded()
                }
            }
        )
    }

    private func runPendingExternalDiskReconciliationIfNeeded() async {
        guard pendingExternalDiskCheck else { return }
        guard saveTask == nil else { return }
        pendingExternalDiskCheck = false
        await processExternalDiskActivity()
    }

    private func processExternalDiskActivity() async {
        guard !externalEditConflict else { return }
        guard let selectedBaseName, activeDocument != nil else { return }

        let diskDate: Date?
        do {
            diskDate = try await repository.noteModifiedDate(baseName: selectedBaseName)
        } catch {
            lastError = "Failed to read note timestamps: \(error.localizedDescription)"
            return
        }
        guard let diskDate else { return }
        if let lastKnown = lastKnownDiskDate, diskDate <= lastKnown {
            return
        }

        let loadedFromDisk: NoteDocument
        do {
            let raw = try await repository.loadNote(baseName: selectedBaseName)
            loadedFromDisk = EditCommandEngine.apply(.repairMetadata, to: raw)
        } catch {
            lastError = "Failed to read external changes: \(error.localizedDescription)"
            return
        }

        let isDirty = lastPersistedDocument != activeDocument

        if !isDirty {
            if loadedFromDisk == activeDocument {
                lastKnownDiskDate = diskDate
                return
            }
            clearUndoStack()
            activeDocument = loadedFromDisk
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            return
        }

        if loadedFromDisk == activeDocument {
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            return
        }

        pendingConflictDiskDate = diskDate
        externalEditConflict = true
    }
}
