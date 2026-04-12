import AppKit
import Foundation
import MiranNotesCore
import os.log
import SwiftUI

/// Stored undo boundary: full snapshot, or replace-text-only chain (inverse commands for hybrid undo).
private enum UndoCheckpoint {
    case full(NoteDocument)
    case replaceTextOnly(forward: [EditCommand], undoCommands: [EditCommand])
}

/// Drives the “file changed on disk” alert; non-nil means a conflict is being presented.
struct ExternalEditConflict: Identifiable, Equatable {
    let id = UUID()
    var diskDate: Date
    var revisionToken: DocumentRevisionToken?
}

struct ExternalTextComparePayload: Identifiable, Equatable {
    let id = UUID()
    var localText: String
    var diskText: String
}

struct TableEditorPayload: Identifiable {
    let id: UUID
    let jsonlURL: URL
    let schemaURL: URL
}

/// Pending scroll to a wiki-link range after navigating to `noteID` (e.g. from the backlink panel).
struct PendingEditorScroll: Equatable {
    var noteID: UUID
    var range: MiranNotesCore.TextRange
}

/// One row in the sidebar outline (folder tree + notes).
enum SidebarOutlineEntry: Identifiable {
    case folder(FolderEntry, [SidebarOutlineEntry])
    case note(NoteSummary, searchSnippet: String?)

    var id: String {
        switch self {
        case .folder(let f, _):
            return "f:\(f.id.uuidString)"
        case .note(let n, _):
            return "n:\(n.noteID.uuidString)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var noteSummaries: [NoteSummary] = []
    /// Manifest `relativePath` for the open note (stable selection for tests and shell).
    @Published var selectedBaseName: String?
    @Published var activeDocument: NoteDocument?
    @Published var backlinks: [BacklinkItem] = []
    /// When set, the editor scrolls to this range once that note is loaded.
    @Published var pendingEditorScroll: PendingEditorScroll?
    @Published var noteQuery: String = ""
    /// Raw note body text per `noteID`, built asynchronously after `refreshNotes()` for substring search.
    @Published private(set) var bodySearchIndex: [UUID: String] = [:]
    @Published var tableEditorPayload: TableEditorPayload?
    @Published var isLoading = false
    @Published var lastError: String?
    /// Non-nil when load-time adjustment ran, editor fallback fired, or size limit was hit.
    /// Shown as a dismissible advisory banner — the editor is always open.
    @Published var repairAdvisory: RepairAdvisory?
    /// When non-nil, shows the external-edit conflict alert (`diskDate` is the on-disk modification time that triggered it).
    @Published var externalEditConflictAlert: ExternalEditConflict?
    /// Non-blocking hint when disk changes conflict with a dirty buffer (set together with ``externalEditConflictAlert``).
    @Published var diskActivityBanner: String?
    /// Side-by-side compare payload (opened from conflict flow).
    @Published var externalTextCompare: ExternalTextComparePayload?
    /// Cached folder tree for outline UI (kept in sync with `refreshNotes()`).
    @Published var folderCatalog: FolderCatalog = FolderCatalog()

    private let repository: NoteRepository
    private var saveTask: Task<Void, Never>?
    private var vaultWatcher: VaultDirectoryWatcher?
    /// Set when the vault watcher fires; processed after autosave finishes so events are not dropped.
    private var pendingExternalDiskCheck = false
    /// Last snapshot known to match on-disk files (after load or successful save). Used with `activeDocument` to detect dirty state.
    private var lastPersistedDocument: NoteDocument?
    private var lastKnownDiskDate: Date?
    private var lastKnownDiskRevision: DocumentRevisionToken?
    /// Last observed SHA256 of raw `.txt` bytes (hex), aligned with load/save and conflict handling.
    private var lastKnownNoteTextSHA256: String?
    private var undoManager: UndoManager?
    /// Bumped when the selected note identity changes so debounced autosave completions cannot apply stale persistence state.
    private var navigationGeneration = 0
    /// Current cursor offset (UTF-16) in the active editor surface, updated by the coordinator on selection change.
    @Published var editorCursorOffset: Int = 0
    /// Full UTF-16 selection in the active editor (`length == 0` for caret-only).
    @Published var editorTextSelection: MiranNotesCore.TextRange = MiranNotesCore.TextRange(start: 0, length: 0)
    private let undoPolicy: UndoPolicy
    /// One checkpoint per document version: `checkpoints[0]` is the oldest retained state, `checkpoints.last` materializes to `activeDocument` after each recorded edit.
    /// Uses ``UndoCheckpoint/replaceTextOnly`` to avoid retaining full ``NoteDocument`` copies for pure ``EditCommand/replaceText`` steps when inverses apply.
    private var undoCheckpoints: [UndoCheckpoint] = []
    /// One name per undo step (`count == checkpoints.count - 1`).
    private var undoActionNames: [String] = []
    private var lastUndoRegistrationDate: Date?
    private var lastRecordedUndoWasSingleReplaceText = false
    /// Action names for each undo step (internal for tests; same cardinality as former `UndoStep` array).
    var undoHistory: [String] { undoActionNames }
    /// Approximate retained undo state for diagnostics / `swift test` (materialized document sizes plus command overhead for hybrid steps).
    var undoRetentionMemoryEstimateBytes: Int {
        undoCheckpoints.enumerated().reduce(0) { sum, entry in
            let (i, cp) = entry
            let mat = materializeCheckpoint(at: i)
            let cmdOverhead: Int
            if case let .replaceTextOnly(forward, undo) = cp {
                cmdOverhead = (forward.count + undo.count) * 64
            } else {
                cmdOverhead = 0
            }
            return sum + mat.estimatedUndoMemoryBytes + cmdOverhead
        }
    }
    private let commandPipelineContract = CommandPipelineContract()
    /// Public registration API for typed extensions; runs before ``localCommandInterceptors`` (see `ExtensionRegistry` docs).
    let extensionRegistry = ExtensionRegistry()
    private var localCommandInterceptors: [UUID: ([EditCommand], NoteDocument, CommandContext) -> [EditCommand]] = [:]
    /// Insertion-ordered list of interceptor keys, so interceptors fire in registration order.
    private var localCommandInterceptorOrder: [UUID] = []

    private let autosaveDebounceMilliseconds: UInt64
    /// In-memory cache to avoid repeated disk reads during rapid edits. Invalidated after successful save and vault rebuild.
    private var cachedLinkGraph: LinkGraph?
    private var backlinkRefreshTask: Task<Void, Never>?
    private var bodySearchIndexTask: Task<Void, Never>?
    private var bodySearchIndexGeneration = 0
    private var activeNoteFilePresenter: ActiveNoteFilePresenter?

    init(
        repository: NoteRepository,
        autosaveDebounceMilliseconds: UInt64 = 400,
        undoPolicy: UndoPolicy = .defaultPolicy
    ) {
        self.repository = repository
        self.autosaveDebounceMilliseconds = autosaveDebounceMilliseconds
        self.undoPolicy = undoPolicy
    }

    func setUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    func loadVault() {
        Task { @MainActor in
            do {
                let recovery = try await repository.performStartupRecovery()
                if recovery.resumedAndCompletedCount > 0 || recovery.discardedStagingCount > 0 {
                    repairAdvisory = RepairAdvisory.vaultRecoveryNotice(recovery)
                }
            } catch {
                lastError = "Vault recovery failed: \(error.localizedDescription)"
            }
            await refreshNotes()
            do {
                let integrity = try await repository.rebuildLinkGraphFull()
                applyVaultIntegrityAfterLoadIfNeeded(integrity)
                cachedLinkGraph = nil
            } catch {
                lastError = "Link index rebuild failed: \(error.localizedDescription)"
            }
            if selectedBaseName == nil {
                selectedBaseName = noteSummaries.first?.relativePath
            }
            await loadSelectedNote()
            await refreshBacklinks()
            startVaultWatcher()
        }
    }

    private func applyVaultIntegrityAfterLoadIfNeeded(_ result: VaultIntegrityResult) {
        guard !result.isClean, repairAdvisory == nil else { return }
        repairAdvisory = RepairAdvisory.vaultIntegrityNotice(result)
    }

    private func applyVaultIntegrityAfterSave(_ result: VaultIntegrityResult) {
        guard !result.isClean else { return }
        repairAdvisory = RepairAdvisory.vaultIntegrityNotice(result)
    }

    func refreshNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            noteSummaries = try await repository.listNotes()
            folderCatalog = try await repository.loadFolderCatalog()
            scheduleBodySearchIndexRebuild()
        } catch {
            lastError = "Failed to list notes: \(error.localizedDescription)"
        }
    }

    private func scheduleBodySearchIndexRebuild() {
        bodySearchIndexTask?.cancel()
        bodySearchIndexGeneration += 1
        let generation = bodySearchIndexGeneration
        let repo = repository
        bodySearchIndexTask = Task { [weak self] in
            let index: [UUID: String]
            do {
                index = try await repo.buildBodySearchIndex()
            } catch {
                return
            }
            await MainActor.run {
                guard let self else { return }
                guard generation == self.bodySearchIndexGeneration else { return }
                self.bodySearchIndex = index
            }
        }
    }

    /// Hierarchical rows for the sidebar (`FolderCatalog` + notes from `filteredNoteSummaries`).
    var sidebarOutline: [SidebarOutlineEntry] {
        Self.buildSidebarOutline(
            folderCatalog: folderCatalog,
            notes: filteredNoteSummaries,
            parentID: FolderCatalog.rootFolderID,
            searchSnippet: { self.searchSnippet(for: $0) }
        )
    }

    private static func buildSidebarOutline(
        folderCatalog: FolderCatalog,
        notes: [NoteSummary],
        parentID: UUID,
        searchSnippet: (NoteSummary) -> String?
    ) -> [SidebarOutlineEntry] {
        let folders = folderCatalog.childFolders(of: parentID).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let noteList = notes.filter { $0.folderID == parentID }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        var rows: [SidebarOutlineEntry] = []
        for f in folders {
            let children = buildSidebarOutline(
                folderCatalog: folderCatalog,
                notes: notes,
                parentID: f.id,
                searchSnippet: searchSnippet
            )
            rows.append(.folder(f, children))
        }
        for n in noteList {
            rows.append(.note(n, searchSnippet: searchSnippet(n)))
        }
        return rows
    }

    /// Optional body snippet when the search query matches note text (see `SearchSnippetBuilder`).
    func searchSnippet(for summary: NoteSummary) -> String? {
        let q = noteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let ql = q.lowercased()
        let body: String
        if let doc = activeDocument, doc.metadata.noteID == summary.noteID {
            body = doc.text
        } else if let cached = bodySearchIndex[summary.noteID] {
            body = cached
        } else {
            return nil
        }
        guard body.lowercased().contains(ql) else { return nil }
        return SearchSnippetBuilder.snippet(for: q, in: body)
    }

    private func noteMatchesSearchQuery(_ summary: NoteSummary, queryLowercased q: String) -> Bool {
        if summary.relativePath.lowercased().contains(q) { return true }
        if summary.title.lowercased().contains(q) { return true }
        let body: String
        if let doc = activeDocument, doc.metadata.noteID == summary.noteID {
            body = doc.text
        } else if let cached = bodySearchIndex[summary.noteID] {
            body = cached
        } else {
            return false
        }
        return body.lowercased().contains(q)
    }

    func createFolder(parentID: UUID = FolderCatalog.rootFolderID, name: String = "New Folder") {
        Task { @MainActor in
            do {
                _ = try await repository.createFolder(parentID: parentID, name: name)
                await refreshNotes()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func deleteFolder(id: UUID) {
        Task { @MainActor in
            do {
                try await repository.deleteFolder(id: id)
                await refreshNotes()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func deleteSelectedNote() {
        guard let path = selectedBaseName else { return }
        Task { @MainActor in
            do {
                let manifest = try await repository.loadManifest()
                guard let id = manifest.entry(relativePath: path)?.noteID else { return }
                try await repository.deleteNote(noteID: id)
                await refreshNotes()
                if noteSummaries.isEmpty {
                    selectedBaseName = nil
                } else {
                    selectedBaseName = noteSummaries.first?.relativePath
                }
                await loadSelectedNote()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Filtered list for search / query UI (title, path, and indexed body text).
    var filteredNoteSummaries: [NoteSummary] {
        let q = noteQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return noteSummaries }
        return noteSummaries.filter { noteMatchesSearchQuery($0, queryLowercased: q) }
    }

    func refreshBacklinks() async {
        guard let doc = activeDocument else {
            backlinks = []
            return
        }
        let targetNoteID = doc.metadata.noteID
        do {
            let graph: LinkGraph
            if let cached = cachedLinkGraph {
                graph = cached
            } else {
                let loaded = try await repository.loadLinkGraph()
                cachedLinkGraph = loaded
                graph = loaded
            }
            let resolver = try await repository.linkResolver()
            let sourceIDs = graph.backlinks(to: targetNoteID)
            var result: [BacklinkItem] = []
            for sid in sourceIDs {
                guard let relPath = resolver.baseName(forTargetNoteID: sid) else { continue }
                let title =
                    noteSummaries.first(where: { $0.noteID == sid })?.title
                    ?? (relPath as NSString).lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
                var snippet = ""
                var linkRange = MiranNotesCore.TextRange(start: 0, length: 0)
                if let sourceResult = try? await repository.loadNote(noteID: sid) {
                    let sourceDoc = sourceResult.document
                    if let link = sourceDoc.metadata.links.first(where: { $0.targetNoteID == targetNoteID }) {
                        linkRange = link.range
                        snippet = BacklinkSnippetBuilder.snippet(around: link.range, in: sourceDoc.text)
                    }
                }
                result.append(
                    BacklinkItem(
                        sourceNoteID: sid,
                        title: title,
                        relativePath: relPath,
                        snippet: snippet,
                        linkRange: linkRange
                    )
                )
            }
            backlinks = result
        } catch {
            backlinks = []
            lastError = "Could not refresh backlinks: \(error.localizedDescription)"
        }
    }

    private func scheduleBacklinkRefresh() {
        backlinkRefreshTask?.cancel()
        backlinkRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            await self.refreshBacklinks()
        }
    }

    func openNote(noteID: UUID) {
        guard noteSummaries.contains(where: { $0.noteID == noteID }) else {
            lastError = "Could not open note (not in vault list)."
            return
        }
        pendingEditorScroll = nil
        changeSelection(noteID: noteID)
    }

    func openBacklinkSource(_ item: BacklinkItem) {
        if !item.linkRange.isEmpty {
            pendingEditorScroll = PendingEditorScroll(noteID: item.sourceNoteID, range: item.linkRange)
        } else {
            pendingEditorScroll = nil
        }
        if activeDocument?.metadata.noteID == item.sourceNoteID {
            return
        }
        changeSelection(noteID: item.sourceNoteID)
    }

    func clearPendingEditorScroll() {
        pendingEditorScroll = nil
    }

    func insertWikiLink(to targetNoteID: UUID, displayText: String? = nil) {
        guard let doc = activeDocument else { return }
        let text = displayText ?? (noteSummaries.first { $0.noteID == targetNoteID }?.title ?? "note")
        let docLength = RangeNormalizer.utf16Length(of: doc.text)
        let offset = min(max(0, editorCursorOffset), docLength)
        apply([.insertWikiLink(utf16Offset: offset, targetNoteID: targetNoteID, displayText: text)])
    }

    func renameActiveNote(newTitle: String) {
        guard let oldPath = selectedBaseName else { return }
        Task { @MainActor in
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            do {
                let newPath = try await repository.renameNote(from: oldPath, to: newTitle)
                await refreshNotes()
                selectedBaseName = newPath
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
                let (document, relPath) = try await repository.createNote(named: "untitled-note")
                await refreshNotes()
                selectedBaseName = relPath
                activeDocument = document
                lastPersistedDocument = document
                await refreshOnDiskFingerprints(for: relPath)
                clearUndoStack()
            } catch {
                lastError = "Failed to create note: \(error.localizedDescription)"
            }
        }
    }

    func loadSelectedNote() async {
        editorCursorOffset = 0
        editorTextSelection = MiranNotesCore.TextRange(start: 0, length: 0)
        guard let path = selectedBaseName else {
            pendingEditorScroll = nil
            activeDocument = nil
            lastPersistedDocument = nil
            lastKnownDiskDate = nil
            lastKnownDiskRevision = nil
            lastKnownNoteTextSHA256 = nil
            repairAdvisory = nil
            backlinks = []
            clearUndoStack()
            updateActiveNoteFilePresenter()
            return
        }
        do {
            let result = try await repository.loadNote(baseName: path)
            activeDocument = result.document
            lastPersistedDocument = result.document
            repairAdvisory = RepairDiagnosticsBuilder.buildLoadAdvisory(result: result)
            await refreshOnDiskFingerprints(for: path)
            clearUndoStack()
            await refreshBacklinks()
        } catch {
            lastError = "Failed to load note: \(error.localizedDescription)"
        }
        updateActiveNoteFilePresenter()
    }

    func dismissRepairAdvisory() {
        repairAdvisory = nil
    }

    func presentFullBufferAdvisory() {
        repairAdvisory = RepairAdvisory(
            kind: .fullBufferFallback,
            title: "We updated how this note is structured",
            explanation:
                "A large edit happened in one step, so section information may differ slightly from before. What you see on screen is unchanged.",
            detailsPlainText: RepairAdvisory.fullBufferDetails
        )
    }

    func presentSizeLimitAdvisory() {
        repairAdvisory = RepairAdvisory(
            kind: .sizeLimitExceeded,
            title: "This note can't grow further",
            explanation: "This note is at the maximum size, so the new text was not added.",
            detailsPlainText: RepairAdvisory.sizeLimitDetails
        )
    }

    func revealSelectedNoteFileInFinder() {
        guard let path = selectedBaseName else { return }
        let url = VaultPath.fileURL(vaultRoot: repository.vaultURL, relativePathWithoutExtension: path, extension: "txt")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    func apply(_ command: EditCommand) -> NoteDocument {
        apply([command])
    }

    @discardableResult
    func registerCommandInterceptor(_ interceptor: @escaping ([EditCommand], NoteDocument, CommandContext) -> [EditCommand]) -> UUID {
        let token = UUID()
        localCommandInterceptors[token] = interceptor
        localCommandInterceptorOrder.append(token)
        return token
    }

    func removeCommandInterceptor(_ token: UUID) {
        localCommandInterceptors.removeValue(forKey: token)
        localCommandInterceptorOrder.removeAll { $0 == token }
    }

    /// Runs ``ExtensionRegistry`` interceptors first (sorted by each extension's `descriptor.id`), then each local interceptor in ``registerCommandInterceptor`` order. The `document` passed to interceptors is the buffer **before** this batch is applied.
    @discardableResult
    func apply(_ commands: [EditCommand], recordUndo: Bool = true) -> NoteDocument {
        guard var doc = activeDocument else { return activeDocument ?? NoteDocument(text: "", metadata: .empty) }
        let maxBatch = commandPipelineContract.maxCommandsPerBatch
        if commands.count > maxBatch {
            assertionFailure("Command batch of \(commands.count) exceeds contract limit \(maxBatch); tail silently dropped")
            Logger.editEngine.error("Command batch truncated from \(commands.count, privacy: .public) to \(maxBatch, privacy: .public)")
        }
        let sanitized = Array(commands.prefix(maxBatch))
        let context = CommandContext(trigger: "appModel.apply", selectionRange: editorTextSelection)
        var intercepted = extensionRegistry.applyInterceptors(to: sanitized, document: doc, context: context)
        intercepted = localCommandInterceptorOrder.reduce(intercepted) { partial, token in
            guard let interceptor = localCommandInterceptors[token] else { return partial }
            return interceptor(partial, doc, context)
        }
        let before = doc
        for command in intercepted {
            doc = EditCommandEngine.apply(command, to: doc)
        }
        guard doc != before else { return doc }

        if recordUndo, undoManager != nil {
            let after = doc
            let name = Self.undoActionName(for: intercepted)
            let singleReplace = Self.isSingleReplaceTextOnly(intercepted)
            let now = Date()
            let windowSeconds = Double(undoPolicy.coalesceReplaceTextWindowNanoseconds) / 1_000_000_000.0

            let lastMatchesBefore =
                !undoCheckpoints.isEmpty
                && materializeCheckpoint(at: undoCheckpoints.count - 1) == before

            let canTryCoalesce =
                undoPolicy.coalesceReplaceTextWindowNanoseconds > 0
                && singleReplace
                && lastRecordedUndoWasSingleReplaceText
                && lastMatchesBefore

            var didCoalesce = false
            if canTryCoalesce, let lastDate = lastUndoRegistrationDate {
                let elapsed = now.timeIntervalSince(lastDate)
                if elapsed < windowSeconds {
                    let lastIdx = undoCheckpoints.count - 1
                    let beforeIdx = lastIdx - 1
                    let docBeforeStep = materializeCheckpoint(at: beforeIdx)
                    switch undoCheckpoints[lastIdx] {
                    case .replaceTextOnly(let forward, _):
                        let combined = forward + intercepted
                        if let rebuilt = UndoInverseSupport.replaceTextChainUndoCommands(forward: combined, documentBefore: docBeforeStep),
                           rebuilt.after == after {
                            undoCheckpoints[lastIdx] = .replaceTextOnly(forward: combined, undoCommands: rebuilt.undoCommands)
                        } else {
                            undoCheckpoints[lastIdx] = .full(after)
                        }
                    case .full:
                        undoCheckpoints[lastIdx] = .full(after)
                    }
                    if !undoActionNames.isEmpty {
                        undoActionNames[undoActionNames.count - 1] = name
                    }
                    reregisterAllUndoActions()
                    didCoalesce = true
                }
            }

            if !didCoalesce {
                if undoCheckpoints.isEmpty {
                    let second = Self.checkpointForRecordedStep(after: after, before: before, intercepted: intercepted)
                    undoCheckpoints = [.full(before), second]
                    undoActionNames = [name]
                    let top = 1
                    undoManager?.registerUndo(withTarget: self) { model in
                        model.applyCheckpointUndo(fromIndex: top, toIndex: top - 1)
                    }
                    undoManager?.setActionName(name)
                } else {
                    assert(materializeCheckpoint(at: undoCheckpoints.count - 1) == before)
                    let newCheckpoint = Self.checkpointForRecordedStep(after: after, before: before, intercepted: intercepted)
                    undoCheckpoints.append(newCheckpoint)
                    undoActionNames.append(name)
                    let top = undoCheckpoints.count - 1
                    undoManager?.registerUndo(withTarget: self) { model in
                        model.applyCheckpointUndo(fromIndex: top, toIndex: top - 1)
                    }
                    undoManager?.setActionName(name)
                }
            }

            lastRecordedUndoWasSingleReplaceText = singleReplace
            lastUndoRegistrationDate = now
            enforceUndoPolicyIfNeeded()
        }

        activeDocument = doc
        scheduleAutosave()
        scheduleBacklinkRefresh()
        return doc
    }

    private func applyCheckpointUndo(fromIndex: Int, toIndex: Int) {
        guard undoCheckpoints.indices.contains(toIndex) else { return }
        activeDocument = materializeCheckpoint(at: toIndex)
        scheduleAutosave()
        scheduleBacklinkRefresh()
        undoManager?.registerUndo(withTarget: self) { model in
            model.applyCheckpointUndo(fromIndex: toIndex, toIndex: fromIndex)
        }
    }

    /// Materializes the document at the given checkpoint index (index 0 is always a full snapshot).
    private func materializeCheckpoint(at index: Int) -> NoteDocument {
        switch undoCheckpoints[index] {
        case .full(let d):
            return d
        case .replaceTextOnly(let forward, _):
            var doc = materializeCheckpoint(at: index - 1)
            for c in forward {
                doc = EditCommandEngine.apply(c, to: doc)
            }
            return doc
        }
    }

    private static func checkpointForRecordedStep(
        after: NoteDocument,
        before: NoteDocument,
        intercepted: [EditCommand]
    ) -> UndoCheckpoint {
        if let chain = UndoInverseSupport.replaceTextChainUndoCommands(forward: intercepted, documentBefore: before),
           chain.after == after {
            return .replaceTextOnly(forward: intercepted, undoCommands: chain.undoCommands)
        }
        return .full(after)
    }

    private func reregisterAllUndoActions() {
        undoManager?.removeAllActions(withTarget: self)
        guard undoCheckpoints.count >= 2 else { return }
        for i in 1..<undoCheckpoints.count {
            let fromIdx = i
            let toIdx = i - 1
            let name = undoActionNames[i - 1]
            undoManager?.registerUndo(withTarget: self) { model in
                model.applyCheckpointUndo(fromIndex: fromIdx, toIndex: toIdx)
            }
            undoManager?.setActionName(name)
        }
    }

    private func clearUndoStack() {
        undoManager?.removeAllActions(withTarget: self)
        undoCheckpoints.removeAll()
        undoActionNames.removeAll()
        lastUndoRegistrationDate = nil
        lastRecordedUndoWasSingleReplaceText = false
    }

    private func enforceUndoPolicyIfNeeded() {
        let max = undoPolicy.maxUndoSteps
        let steps = undoCheckpoints.count - 1
        guard steps > max else { return }
        let dropCount = steps - max
        // Rebasing: `suffix` would leave a `.replaceTextOnly` at index 0 without its parent. Materialize each
        // retained checkpoint to `.full` so the timeline stays self-contained after pruning.
        let newCheckpoints: [UndoCheckpoint] = (dropCount..<undoCheckpoints.count).map { i in
            .full(materializeCheckpoint(at: i))
        }
        undoCheckpoints = newCheckpoints
        undoActionNames = Array(undoActionNames.suffix(max))
        reregisterAllUndoActions()
        Logger.vault.info("Undo stack pruned to \(max, privacy: .public) steps")
    }

    private static func isSingleReplaceTextOnly(_ commands: [EditCommand]) -> Bool {
        guard commands.count == 1, case .replaceText = commands[0] else { return false }
        return true
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
                case (.replaceText, .replaceMetadataBlocks):
                    return "Full Buffer Edit"
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
            case .replaceMetadataBlocks: return "Recover Blocks"
            case .duplicateBlock: return "Duplicate Block"
            case .deleteBlock: return "Delete Block"
            }
        })
        if kinds.count == 1, let only = kinds.first {
            return only
        }
        return "Edit"
    }

    func changeSelection(baseName: String?) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        Task { @MainActor in
            if selectedBaseName == baseName { return }
            if let p = pendingEditorScroll, let path = baseName {
                let manifest = try? await repository.loadManifest()
                let newID = manifest?.entry(relativePath: path)?.noteID
                if newID != p.noteID { pendingEditorScroll = nil }
            } else if baseName == nil {
                pendingEditorScroll = nil
            }
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            selectedBaseName = baseName
            await loadSelectedNote()
        }
    }

    func changeSelection(noteID: UUID?) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        Task { @MainActor in
            let path: String?
            if let id = noteID {
                do {
                    let manifest = try await repository.loadManifest()
                    path = manifest.entry(noteID: id)?.relativePath
                } catch {
                    path = nil
                }
            } else {
                path = nil
            }
            if selectedBaseName == path, activeDocument?.metadata.noteID == noteID { return }
            if let p = pendingEditorScroll, p.noteID != noteID {
                pendingEditorScroll = nil
            }
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            selectedBaseName = path
            await loadSelectedNote()
        }
    }

    private func refreshOnDiskFingerprints(for path: String) async {
        do {
            lastKnownDiskDate = try await repository.noteModifiedDate(relativePath: path)
            lastKnownDiskRevision = try await repository.noteRevisionToken(relativePath: path)
            lastKnownNoteTextSHA256 = try await repository.noteTextFileSHA256(relativePath: path)
        } catch {
            lastError = "Failed to read note on-disk state: \(error.localizedDescription)"
        }
    }

    /// Cancels any debounced save, then persists the current buffer if it differs from the last known on-disk snapshot.
    private func flushCurrentNoteToDiskIfDirty() async {
        saveTask?.cancel()
        saveTask = nil
        guard let doc = activeDocument, let path = selectedBaseName else { return }
        guard doc != lastPersistedDocument else { return }
        do {
            let integrity = try await repository.save(doc, asBaseName: path)
            applyVaultIntegrityAfterSave(integrity)
            await refreshOnDiskFingerprints(for: path)
            lastPersistedDocument = doc
            cachedLinkGraph = nil
            await refreshBacklinks()
        } catch {
            lastError = "Autosave failed: \(error.localizedDescription)"
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        guard let expectedPath = selectedBaseName, activeDocument != nil else { return }
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
            guard selectedBaseName == expectedPath else { return }
            guard let latest = activeDocument else { return }
            do {
                let integrity = try await repository.save(latest, asBaseName: expectedPath)
                guard gen == navigationGeneration, selectedBaseName == expectedPath else { return }
                applyVaultIntegrityAfterSave(integrity)
                await refreshOnDiskFingerprints(for: expectedPath)
                lastPersistedDocument = latest
                cachedLinkGraph = nil
                let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VaultTelemetry.logAutosave(latencyMs: max(0, latencyMs))
                await self.refreshBacklinks()
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
        diskActivityBanner = nil
        if reloadFromDisk {
            Task { @MainActor in
                await loadSelectedNote()
            }
        } else if let path = selectedBaseName {
            Task { @MainActor in
                await refreshOnDiskFingerprints(for: path)
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
        guard let path = selectedBaseName, activeDocument != nil else { return }

        let diskDate: Date?
        let diskRevision: DocumentRevisionToken?
        do {
            diskDate = try await repository.noteModifiedDate(relativePath: path)
            diskRevision = try await repository.noteRevisionToken(relativePath: path)
        } catch {
            lastError = "Failed to read note timestamps: \(error.localizedDescription)"
            return
        }
        guard let diskDate else { return }
        if let diskRevision, diskRevision == lastKnownDiskRevision {
            lastKnownDiskDate = diskDate
            if let h = try? await repository.noteTextFileSHA256(relativePath: path) {
                lastKnownNoteTextSHA256 = h
            }
            return
        }
        if let lastKnown = lastKnownDiskDate, diskDate <= lastKnown {
            return
        }

        let observedTextHash: String
        do {
            let h1 = try await repository.noteTextFileSHA256(relativePath: path)
            let h2 = try await repository.noteTextFileSHA256(relativePath: path)
            if h1 != h2 {
                VaultTelemetry.logToctouTextHashDrift()
            }
            observedTextHash = h2
        } catch {
            lastError = "Failed to read note body fingerprint: \(error.localizedDescription)"
            return
        }

        let loadedFromDisk: NoteDocument
        do {
            let raw = try await repository.loadNote(baseName: path)
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
                lastKnownNoteTextSHA256 = observedTextHash
                return
            }
            clearUndoStack()
            activeDocument = loadedFromDisk
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            lastKnownDiskRevision = diskRevision
            lastKnownNoteTextSHA256 = observedTextHash
            Task { await refreshBacklinks() }
            return
        }

        if loadedFromDisk == activeDocument {
            lastPersistedDocument = loadedFromDisk
            lastKnownDiskDate = diskDate
            lastKnownDiskRevision = diskRevision
            lastKnownNoteTextSHA256 = observedTextHash
            return
        }

        VaultTelemetry.logConflictDetected(isDirty: isDirty, hasRevisionToken: diskRevision != nil)
        diskActivityBanner =
            "The saved copy of this note changed on disk while you have unsaved edits. Choose an action below or compare versions."
        externalEditConflictAlert = ExternalEditConflict(diskDate: diskDate, revisionToken: diskRevision)
    }

    func openExternalEditCompare() {
        guard let path = selectedBaseName, let doc = activeDocument else { return }
        Task { @MainActor in
            let diskText: String
            do {
                diskText = try await repository.readRawNoteText(relativePath: path)
            } catch {
                lastError = "Could not load disk copy: \(error.localizedDescription)"
                return
            }
            externalTextCompare = ExternalTextComparePayload(localText: doc.text, diskText: diskText)
        }
    }

    func dismissDiskActivityBanner() {
        diskActivityBanner = nil
    }

    private func updateActiveNoteFilePresenter() {
        activeNoteFilePresenter?.stop()
        activeNoteFilePresenter = nil
        guard let path = selectedBaseName else { return }
        let url = VaultPath.fileURL(vaultRoot: repository.vaultURL, relativePathWithoutExtension: path, extension: "txt")
        let presenter = ActiveNoteFilePresenter(fileURL: url) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.pendingExternalDiskCheck = true
                await self.runPendingExternalDiskReconciliationIfNeeded()
            }
        }
        presenter.start()
        activeNoteFilePresenter = presenter
    }
}
