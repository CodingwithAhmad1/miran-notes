import Foundation
import MiranNotesCore
import os.log
import SwiftUI

/// Drives the “file changed on disk” alert; non-nil means a conflict is being presented.
struct ExternalEditConflict: Identifiable, Equatable {
    let id = UUID()
    var diskDate: Date
    var revisionToken: DocumentRevisionToken?
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
    /// Non-nil when load-time structural repair ran or wiki-link metadata is missing.
    /// Shown as a dismissible advisory banner — the editor is always open.
    @Published var repairNotice: String?
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
    private var lastKnownDiskRevision: DocumentRevisionToken?
    private var undoManager: UndoManager?
    /// Bumped when the selected note identity changes so debounced autosave completions cannot apply stale persistence state.
    private var navigationGeneration = 0
    /// Current cursor offset (UTF-16) in the active editor surface, updated by the coordinator on selection change.
    @Published var editorCursorOffset: Int = 0
    private let undoPolicy = UndoPolicy.defaultPolicy
    private var approxUndoSnapshotBytes = 0
    private let commandPipelineContract = CommandPipelineContract()
    private var localCommandInterceptors: [([EditCommand], NoteDocument, CommandContext) -> [EditCommand]] = []

    private let autosaveDebounceMilliseconds: UInt64

    init(repository: NoteRepository, autosaveDebounceMilliseconds: UInt64 = 400) {
        self.repository = repository
        self.autosaveDebounceMilliseconds = autosaveDebounceMilliseconds
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
            lastError = "Could not refresh backlinks: \(error.localizedDescription)"
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
        let docLength = RangeNormalizer.utf16Length(of: doc.text)
        let offset = min(max(0, editorCursorOffset), docLength)
        apply([.insertWikiLink(utf16Offset: offset, targetNoteID: targetNoteID, displayText: text)])
    }

    func renameActiveNote(newTitle: String) {
        guard let oldBase = selectedBaseName else { return }
        Task { @MainActor in
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
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
        guard let doc = activeDocument else { return }
        let noteID = doc.metadata.noteID
        let artifactID = UUID()
        Task { @MainActor in
            do {
                let paths = try TableDocumentFactory.bootstrapEmptyTable(
                    vaultURL: repository.vaultURL,
                    noteID: noteID,
                    artifactID: artifactID
                )
                // Register the artifact in the model — scheduleAutosave handles persistence.
                apply([.registerTableArtifact(artifactID: artifactID, relativePath: paths.relativePath)])
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
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            do {
                let (document, baseName) = try await repository.createNote(named: "untitled-note")
                await refreshNotes()
                selectedBaseName = baseName
                activeDocument = document
                lastPersistedDocument = document
                do {
                    lastKnownDiskDate = try await repository.noteModifiedDate(baseName: baseName)
                    lastKnownDiskRevision = try await repository.noteRevisionToken(baseName: baseName)
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
            lastKnownDiskRevision = nil
            repairNotice = nil
            backlinks = []
            clearUndoStack()
            return
        }
        do {
            let result = try await repository.loadNote(baseName: selectedBaseName)
            activeDocument = result.document
            lastPersistedDocument = result.document
            repairNotice = Self.buildRepairNotice(result: result)
            do {
                lastKnownDiskDate = try await repository.noteModifiedDate(baseName: selectedBaseName)
                lastKnownDiskRevision = try await repository.noteRevisionToken(baseName: selectedBaseName)
            } catch {
                lastError = "Failed to read note timestamps: \(error.localizedDescription)"
            }
            clearUndoStack()
            await refreshBacklinks()
        } catch {
            lastError = "Failed to load note: \(error.localizedDescription)"
        }
    }

    private static func buildRepairNotice(result: NoteLoadResult) -> String? {
        var parts: [String] = []

        if result.wasRepaired {
            parts.append("Block structure was repaired on load — metadata may not perfectly reflect the original block types.")
        }

        let text = result.document.text
        let hasWikiSyntax = text.contains("[[")
        let hasMissingLinkMetadata = hasWikiSyntax && result.document.metadata.links.isEmpty
        if hasMissingLinkMetadata {
            parts.append("Note contains [[link]] syntax with no recorded link metadata. Links will not be navigable until re-created in the editor.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    @discardableResult
    func apply(_ command: EditCommand) -> NoteDocument {
        apply([command])
    }

    func registerCommandInterceptor(_ interceptor: @escaping ([EditCommand], NoteDocument, CommandContext) -> [EditCommand]) {
        localCommandInterceptors.append(interceptor)
    }

    @discardableResult
    func apply(_ commands: [EditCommand], recordUndo: Bool = true) -> NoteDocument {
        guard var doc = activeDocument else { return activeDocument ?? NoteDocument(text: "", metadata: .empty) }
        let sanitized = Array(commands.prefix(commandPipelineContract.maxCommandsPerBatch))
        let context = CommandContext(trigger: "appModel.apply", selectionRange: nil)
        let intercepted = localCommandInterceptors.reduce(sanitized) { partial, interceptor in
            interceptor(partial, doc, context)
        }
        let before = doc
        for command in intercepted {
            doc = EditCommandEngine.apply(command, to: doc)
        }
        guard doc != before else { return doc }

        if recordUndo, let undo = undoManager {
            let after = doc
            let beforeCost = before.text.utf16.count + before.metadata.blocks.count * 64 + before.metadata.spans.count * 48
            let afterCost = after.text.utf16.count + after.metadata.blocks.count * 64 + after.metadata.spans.count * 48
            undo.registerUndo(withTarget: self) { model in
                model.applyUndoSnapshot(from: after, to: before)
            }
            undo.setActionName(Self.undoActionName(for: intercepted))
            approxUndoSnapshotBytes += beforeCost + afterCost
            enforceUndoPolicyIfNeeded()
        }

        activeDocument = doc
        scheduleAutosave()
        Task { await refreshBacklinks() }
        return doc
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
        approxUndoSnapshotBytes = 0
    }

    private func enforceUndoPolicyIfNeeded() {
        guard approxUndoSnapshotBytes > undoPolicy.maxApproxBytes else { return }
        clearUndoStack()
        Logger.vault.info("Undo stack pruned due to policy cap=\(self.undoPolicy.maxApproxBytes, privacy: .public)")
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
        Task { @MainActor in
            if selectedBaseName == baseName { return }
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            selectedBaseName = baseName
            await loadSelectedNote()
        }
    }

    /// Cancels any debounced save, then persists the current buffer if it differs from the last known on-disk snapshot.
    private func flushCurrentNoteToDiskIfDirty() async {
        saveTask?.cancel()
        saveTask = nil
        guard let doc = activeDocument, let baseName = selectedBaseName else { return }
        guard doc != lastPersistedDocument else { return }
        do {
            try await repository.save(doc, asBaseName: baseName)
            let modified = try await repository.noteModifiedDate(baseName: baseName)
            let revision = try await repository.noteRevisionToken(baseName: baseName)
            lastKnownDiskDate = modified
            lastKnownDiskRevision = revision
            lastPersistedDocument = doc
            await refreshBacklinks()
        } catch {
            lastError = "Autosave failed: \(error.localizedDescription)"
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        guard let expectedBaseName = selectedBaseName, activeDocument != nil else { return }
        let gen = navigationGeneration
        let startedAt = Date()
        saveTask = Task { @MainActor in
            defer {
                Task { @MainActor in
                    self.saveTask = nil
                    await self.runPendingExternalDiskReconciliationIfNeeded()
                }
            }
            try? await Task.sleep(for: .milliseconds(autosaveDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            guard gen == navigationGeneration else { return }
            guard selectedBaseName == expectedBaseName else { return }
            guard let latest = activeDocument else { return }
            do {
                try await repository.save(latest, asBaseName: expectedBaseName)
                let modified = try await repository.noteModifiedDate(baseName: expectedBaseName)
                let revision = try await repository.noteRevisionToken(baseName: expectedBaseName)
                guard gen == navigationGeneration, selectedBaseName == expectedBaseName else { return }
                lastKnownDiskDate = modified
                lastKnownDiskRevision = revision
                lastPersistedDocument = latest
                let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VaultTelemetry.logAutosave(latencyMs: max(0, latencyMs))
                Task { await self.refreshBacklinks() }
            } catch {
                lastError = "Autosave failed: \(error.localizedDescription)"
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
        let diskRevision = externalEditConflictAlert?.revisionToken
        externalEditConflictAlert = nil
        if reloadFromDisk {
            Task { @MainActor in
                await loadSelectedNote()
            }
        } else if let diskDate {
            lastKnownDiskDate = diskDate
            lastKnownDiskRevision = diskRevision
        }
    }

    /// Test helper: mirrors what the vault watcher closure does without relying on filesystem events.
    func simulateWatcherEvent() async {
        pendingExternalDiskCheck = true
        await runPendingExternalDiskReconciliationIfNeeded()
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

    func runPendingExternalDiskReconciliationIfNeeded() async {
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
        let diskRevision: DocumentRevisionToken?
        do {
            diskDate = try await repository.noteModifiedDate(baseName: selectedBaseName)
            diskRevision = try await repository.noteRevisionToken(baseName: selectedBaseName)
        } catch {
            lastError = "Failed to read note timestamps: \(error.localizedDescription)"
            return
        }
        guard let diskDate else { return }
        if let diskRevision, diskRevision == lastKnownDiskRevision {
            lastKnownDiskDate = diskDate
            return
        }
        if let lastKnown = lastKnownDiskDate, diskDate <= lastKnown {
            return
        }

        let loadedFromDisk: NoteDocument
        do {
            let raw = try await repository.loadNote(baseName: selectedBaseName)
            loadedFromDisk = EditCommandEngine.apply(.repairMetadata, to: raw.document)
        } catch {
            lastError = "Failed to read external changes: \(error.localizedDescription)"
            return
        }

        let isDirty = lastPersistedDocument != activeDocument

        if !isDirty {
            if loadedFromDisk == activeDocument {
                lastKnownDiskDate = diskDate
                lastKnownDiskRevision = diskRevision
                return
            }
            clearUndoStack()
            activeDocument = loadedFromDisk
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            lastKnownDiskRevision = diskRevision
            Task { await refreshBacklinks() }
            return
        }

        if loadedFromDisk == activeDocument {
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            lastKnownDiskRevision = diskRevision
            return
        }

        VaultTelemetry.logConflictDetected(isDirty: isDirty, hasRevisionToken: diskRevision != nil)
        externalEditConflictAlert = ExternalEditConflict(diskDate: diskDate, revisionToken: diskRevision)
    }
}
