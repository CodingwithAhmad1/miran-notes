import Foundation
import MiranNotesCore
import SwiftUI

/// Drives the “file changed on disk” alert; non-nil means a conflict is being presented.
struct ExternalEditConflict: Identifiable, Equatable {
    let id = UUID()
    var diskDate: Date
}

struct TableEditorPayload: Identifiable {
    let id: UUID
    let jsonlURL: URL
    let schemaURL: URL
}

@MainActor
final class AppModel: ObservableObject {
    @Published var noteSummaries: [NoteSummary] = []
    @Published var selectedBaseName: String?
    @Published var activeDocument: NoteDocument?
    @Published var backlinks: [NoteSummary] = []
    @Published var noteQuery: String = ""
    @Published var tableEditorPayload: TableEditorPayload?
    @Published var isLoading = false
    @Published var lastError: String?
    /// When non-nil, shows the external-edit conflict alert (`diskDate` is the on-disk modification time that triggered it).
    @Published var externalEditConflictAlert: ExternalEditConflict?

    private let repository: NoteRepository
    private var saveTask: Task<Void, Never>?
    private var vaultWatcher: VaultDirectoryWatcher?
    /// Set when the vault watcher fires; processed after autosave finishes so events are not dropped.
    private var pendingExternalDiskCheck = false
    /// Last snapshot known to match on-disk files (after load or successful save). Used with `activeDocument` to detect dirty state.
    private var lastPersistedDocument: NoteDocument?
    private var lastKnownDiskDate: Date?
    private var undoManager: UndoManager?

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func setUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    func loadVault() {
        Task { @MainActor in
            await refreshNotes()
            do {
                try await repository.rebuildLinkGraphFull()
            } catch {
                lastError = "Link index rebuild failed: \(error.localizedDescription)"
            }
            if selectedBaseName == nil {
                selectedBaseName = noteSummaries.first?.baseName
            }
            await loadSelectedNote()
            await refreshBacklinks()
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

    /// Filtered list for search / query UI (title and baseName). Richer queries over `NoteMetadata.properties` can use a dedicated index later.
    var filteredNoteSummaries: [NoteSummary] {
        let q = noteQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return noteSummaries }
        return noteSummaries.filter { summary in
            summary.baseName.lowercased().contains(q)
                || summary.title.lowercased().contains(q)
        }
    }

    func refreshBacklinks() async {
        guard let doc = activeDocument else {
            backlinks = []
            return
        }
        let id = doc.metadata.noteID
        do {
            let graph = try await repository.loadLinkGraph()
            let resolver = try await repository.linkResolver()
            let sourceIDs = graph.backlinks(to: id)
            var result: [NoteSummary] = []
            for sid in sourceIDs {
                if let base = resolver.baseName(forTargetNoteID: sid),
                   let title = noteSummaries.first(where: { $0.noteID == sid })?.title {
                    result.append(NoteSummary(noteID: sid, title: title, baseName: base))
                } else if let base = resolver.baseName(forTargetNoteID: sid) {
                    result.append(NoteSummary(noteID: sid, title: base, baseName: base))
                }
            }
            backlinks = result
        } catch {
            backlinks = []
        }
    }

    func openNote(noteID: UUID) {
        guard let summary = noteSummaries.first(where: { $0.noteID == noteID }) else {
            lastError = "Could not open note (not in vault list)."
            return
        }
        changeSelection(baseName: summary.baseName)
    }

    func insertWikiLink(to targetNoteID: UUID, displayText: String? = nil) {
        guard let doc = activeDocument else { return }
        let text = displayText ?? (noteSummaries.first { $0.noteID == targetNoteID }?.title ?? "note")
        let offset = RangeNormalizer.utf16Length(of: doc.text)
        apply([.insertWikiLink(utf16Offset: offset, targetNoteID: targetNoteID, displayText: text)])
    }

    func renameActiveNote(newTitle: String) {
        guard let oldBase = selectedBaseName else { return }
        Task { @MainActor in
            do {
                let newBase = try await repository.renameNote(from: oldBase, to: newTitle)
                await refreshNotes()
                selectedBaseName = newBase
                await refreshBacklinks()
            } catch {
                lastError = "Rename failed: \(error.localizedDescription)"
            }
        }
    }

    func addTableToActiveNote() {
        guard let doc = activeDocument, let baseName = selectedBaseName else { return }
        let noteID = doc.metadata.noteID
        let artifactID = UUID()
        Task { @MainActor in
            do {
                let paths = try TableDocumentFactory.bootstrapEmptyTable(
                    vaultURL: repository.vaultURL,
                    noteID: noteID,
                    artifactID: artifactID
                )
                apply([.registerTableArtifact(artifactID: artifactID, relativePath: paths.relativePath)])
                guard let updated = activeDocument else { return }
                try await repository.save(updated, asBaseName: baseName)
                tableEditorPayload = TableEditorPayload(id: artifactID, jsonlURL: paths.jsonl, schemaURL: paths.schema)
            } catch {
                lastError = "Could not create table: \(error.localizedDescription)"
            }
        }
    }

    func openFirstTableArtifact() {
        guard let doc = activeDocument,
              let art = doc.metadata.artifacts.first(where: { $0.kind == .table }) else {
            lastError = "No table on this note."
            return
        }
        let aux = VaultPaths.auxDirectory(vaultURL: repository.vaultURL, noteID: doc.metadata.noteID)
        let jsonl = aux.appendingPathComponent(art.relativePath, isDirectory: false)
        let schemaName = (art.relativePath as NSString).lastPathComponent.replacingOccurrences(of: ".jsonl", with: ".schema.json")
        let schema = jsonl.deletingLastPathComponent().appendingPathComponent(schemaName)
        tableEditorPayload = TableEditorPayload(id: art.id, jsonlURL: jsonl, schemaURL: schema)
    }

    func createNote() {
        Task { @MainActor in
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
            backlinks = []
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
            await refreshBacklinks()
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
        Task { await refreshBacklinks() }
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
                case let (.replaceText(range, replacement), .changeBlockType):
                    if replacement.isEmpty, range.length > 0 {
                        return "Slash Command"
                    }
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
            case .insertWikiLink: return "Insert Link"
            case .registerTableArtifact: return "Add Table"
            case .repairMetadata: return "Repair Note"
            }
        })
        if kinds.count == 1, let only = kinds.first {
            return only
        }
        return "Edit"
    }

    func changeSelection(baseName: String?) {
        externalEditConflictAlert = nil
        selectedBaseName = baseName
        Task { @MainActor in
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
                    Task { await self.refreshBacklinks() }
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Autosave failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func reloadFromDisk() {
        Task { @MainActor in
            await loadSelectedNote()
        }
    }

    /// Dismisses the conflict alert. If `reloadFromDisk` is true, loads the note from the vault (discarding local edits). Otherwise keeps the buffer and records the external file time so the same change does not re-alert until the file changes again.
    func resolveExternalEditConflict(reloadFromDisk: Bool) {
        let diskDate = externalEditConflictAlert?.diskDate
        externalEditConflictAlert = nil
        if reloadFromDisk {
            Task { @MainActor in
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

    /// Package-internal for tests that simulate vault changes without relying on filesystem timing.
    func processExternalDiskActivity() async {
        guard externalEditConflictAlert == nil else { return }
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
            Task { await refreshBacklinks() }
            return
        }

        if loadedFromDisk == activeDocument {
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            return
        }

        externalEditConflictAlert = ExternalEditConflict(diskDate: diskDate)
    }
}
