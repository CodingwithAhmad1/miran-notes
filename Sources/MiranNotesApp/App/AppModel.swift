import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

/// Drives the “file changed on disk” alert; non-nil means a conflict is being presented.
struct ExternalEditConflict: Identifiable, Equatable, Sendable {
    let id = UUID()
    var diskDate: Date
    var revisionToken: DocumentRevisionToken?
}

struct ExternalTextComparePayload: Identifiable, Equatable, Sendable {
    let id = UUID()
    var localText: String
    var diskText: String
}

/// Recovery action offered alongside a user-visible error alert (no `RepairAdvisory` banner).
enum UserAlertRecoveryKind: Equatable, Sendable {
    case retryBodySearchIndex
    case retryVaultStartupRecovery
    case retryStartupLinkGraphSync
    case retryManifestReconcileAfterDiskChange(invalidateCaches: Bool)
    case retryRefreshNotesAndFolderUI
    case retryRefreshBacklinks
    case retryLoadActiveNote
    case retryResolveNoteSelection(noteID: UUID?)
    case retryRefreshOnDiskFingerprints
    case retryFlushActiveNoteToDisk
    case retryVaultWatcher
    case retryProcessExternalDiskActivity
    case retryOpenExternalEditCompare
    case retryLoadViewPane(index: Int, baseName: String)
}

/// Modal error presentation: plain message or retryable async failure.
enum UserAlertState: Equatable {
    case none
    case message(String)
    case recoverable(message: String, kind: UserAlertRecoveryKind)

    var alertMessage: String {
        switch self {
        case .none: return ""
        case .message(let s), .recoverable(let s, _): return s
        }
    }
}

/// Pending scroll to a wiki-link range after navigating to `noteID` (e.g. from the backlink panel).
struct PendingEditorScroll: Equatable, Sendable {
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
@Observable
final class AppModel {
    var noteSummaries: [NoteSummary] = []
    /// Manifest `relativePath` for the open note (stable selection for tests and shell).
    var selectedBaseName: String?
    /// Stable UUID identity of the selected note. This is the canonical UI selection key;
    /// `selectedBaseName` is the companion disk-I/O key kept in sync alongside it.
    var selectedNoteID: UUID?
    var activeDocument: NoteDocument?
    var backlinks: [BacklinkItem] = []
    /// When set, the editor scrolls to this range once that note is loaded.
    var pendingEditorScroll: PendingEditorScroll?
    /// Search string for vault-wide note name / path filtering (folder page and legacy outline).
    var vaultSearchQuery: String = ""
    /// Find-in-note query driven by the detail column search field when a note is open.
    var editorFindQuery: String = ""
    /// Raw note body text per `noteID`, built asynchronously after `refreshNotes()` for substring search.
    private(set) var bodySearchIndex: [UUID: String] = [:]
    /// True while `buildBodySearchIndex` is in flight after the latest `scheduleBodySearchIndexRebuild()` (excludes cancelled superseded work).
    private(set) var isBodySearchIndexBuilding = false
    var isLoading = false
    /// User-visible error alert (generic or with optional recovery — e.g. retry body search index).
    var userAlert: UserAlertState = .none

    var userAlertRecoveryKind: UserAlertRecoveryKind? {
        if case let .recoverable(_, kind) = userAlert { return kind }
        return nil
    }
    /// Non-nil when load-time adjustment ran, editor fallback fired, or size limit was hit.
    /// Shown as a dismissible advisory banner — the editor is always open.
    var repairAdvisory: RepairAdvisory?
    /// When non-nil, shows the external-edit conflict alert (`diskDate` is the on-disk modification time that triggered it).
    var externalEditConflictAlert: ExternalEditConflict?
    /// Non-blocking hint when disk changes conflict with a dirty buffer (set together with ``externalEditConflictAlert``).
    var diskActivityBanner: String?
    /// Side-by-side compare payload (opened from conflict flow).
    var externalTextCompare: ExternalTextComparePayload?
    /// Cached folder tree for outline UI (kept in sync with `refreshNotes()`).
    var folderCatalog: FolderCatalog = FolderCatalog()

    // MARK: - Workspace compatibility & folder-page UI

    enum WorkspaceGateState: Equatable {
        case checking
        case ready
        case incompatible(CompatibilityReport)
    }

    /// Blocks the main shell until the workspace passes ``WorkspaceCompatibilityScanner``.
    var workspaceGateState: WorkspaceGateState = .checking

    /// Selected topic folder (or vault root) for the folder-page column.
    var selectedFolderID: UUID?

    /// When true, the one-time vault welcome in the detail pane will not be shown again for this vault (see ``VaultWelcomeDismissalStore``).
    private(set) var hasDismissedVaultWelcome = false

    var topLevelFolderEntries: [FolderEntry] {
        let parent: UUID
        switch workspaceScope {
        case .fullVault:
            parent = FolderCatalog.rootFolderID
        case .folderSubtree(let rootFolderID):
            parent = rootFolderID
        }
        return folderCatalog.childFolders(of: parent).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var selectedFolderDisplayTitle: String {
        guard let id = selectedFolderID else { return "" }
        return folderCatalog.folder(id: id)?.name ?? ""
    }

    var folderPageNoteSummaries: [NoteSummary] {
        guard let id = selectedFolderID else { return [] }
        return noteSummaries.filter { $0.folderID == id }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var hasRootLevelNotes: Bool {
        switch workspaceScope {
        case .fullVault:
            return noteSummaries.contains { $0.folderID == FolderCatalog.rootFolderID }
        case .folderSubtree(let rootFolderID):
            return noteSummaries.contains { $0.folderID == rootFolderID }
        }
    }

    /// Whether the sidebar may create a note in the current folder (excludes welcome/`nil` and the vault root tray).
    var allowsToolbarNewNote: Bool {
        guard let id = selectedFolderID else { return false }
        return id != FolderCatalog.rootFolderID
    }

    /// Folder ID for the sidebar row that lists notes sitting at the “root” of the visible tree.
    var sidebarNotesTrayFolderID: UUID {
        switch workspaceScope {
        case .fullVault:
            return FolderCatalog.rootFolderID
        case .folderSubtree(let rootFolderID):
            return rootFolderID
        }
    }

    /// Title for the notes tray row (e.g. “Vault” or the scoped folder name).
    var sidebarNotesTrayTitle: String {
        switch workspaceScope {
        case .fullVault:
            return "Vault"
        case .folderSubtree(let rootFolderID):
            return folderCatalog.folder(id: rootFolderID)?.name ?? "Folder"
        }
    }

    /// True when the vault has no notes and no folder to show yet (same condition as ``pickDefaultFolderID()`` returning `nil`).
    var isEmptyVaultOnboardingState: Bool {
        noteSummaries.isEmpty && topLevelFolderEntries.isEmpty && !hasRootLevelNotes
    }

    // MARK: - Layout state

    /// Active pane layout selection. Defaults to single-pane (the original behaviour).
    var currentLayout: PaneLayout = .single
    /// Index of the pane that is currently editable (0 = top-left / first pane).
    var activePaneIndex: Int = 0
    /// State for the non-active (read-only) view panes. Count is always `currentLayout.paneCount - 1`.
    var viewPaneStates: [ViewPaneState] = []

    /// Limits sidebar/navigation to a folder subtree when not ``WorkspaceScope/fullVault``.
    var workspaceScope: WorkspaceScope = .fullVault

    let repository: NoteRepository
    private let manifestRefreshFacade = VaultManifestRefreshFacade()
    private let bodySearchIndexController = NoteBodySearchIndexController()
    private let backlinkRefreshScheduler = DebouncedAsyncWorkScheduler()
    private var saveTask: Task<Void, Never>?
    private var vaultWatcherSubscription: VaultWatcherSubscription?
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
    var editorCursorOffset: Int = 0
    /// Full UTF-16 selection in the active editor (`length == 0` for caret-only).
    var editorTextSelection: MiranNotesCore.TextRange = MiranNotesCore.TextRange(start: 0, length: 0)
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
    private let commandPipelineContract: CommandPipelineContract
    /// Public registration API for typed extensions; runs before ``localCommandInterceptors`` (see `ExtensionRegistry` docs).
    let extensionRegistry = ExtensionRegistry()
    private var localCommandInterceptors: [UUID: ([EditCommand], NoteDocument, CommandContext) -> [EditCommand]] = [:]
    /// Insertion-ordered list of interceptor keys, so interceptors fire in registration order.
    private var localCommandInterceptorOrder: [UUID] = []

    private let autosaveDebounceMilliseconds: UInt64
    private let largeVaultLinkGraphSyncThreshold: Int
    private let startupLinkGraphSyncBudgetMs: Double
    private let startupLinkGraphSyncHistoryWeight: Double
    private var startupLinkGraphSyncTask: Task<Void, Never>?
    private var activeNoteFilePresenter: ActiveNoteFilePresenter?

    init(
        repository: NoteRepository,
        workspaceScope: WorkspaceScope = .fullVault,
        autosaveDebounceMilliseconds: UInt64 = 400,
        undoPolicy: UndoPolicy = .defaultPolicy,
        largeVaultLinkGraphSyncThreshold: Int = 2_000,
        startupLinkGraphSyncBudgetMs: Double = 120,
        startupLinkGraphSyncHistoryWeight: Double = 0.3,
        commandPipelineContract: CommandPipelineContract = CommandPipelineContract()
    ) {
        self.repository = repository
        self.workspaceScope = workspaceScope
        self.autosaveDebounceMilliseconds = autosaveDebounceMilliseconds
        self.undoPolicy = undoPolicy
        self.largeVaultLinkGraphSyncThreshold = largeVaultLinkGraphSyncThreshold
        self.startupLinkGraphSyncBudgetMs = startupLinkGraphSyncBudgetMs
        self.startupLinkGraphSyncHistoryWeight = startupLinkGraphSyncHistoryWeight
        self.commandPipelineContract = commandPipelineContract
        VaultSecurityScopeCoordinator.shared.retain(repository.vaultURL)
    }

    deinit {
        let url = repository.vaultURL
        Task { @MainActor in
            VaultSecurityScopeCoordinator.shared.release(url)
        }
    }

    func setUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    private func runStartupRecoveryIfPossible() async {
        do {
            let recovery = try await repository.performStartupRecovery()
            if recovery.resumedAndCompletedCount > 0 || recovery.discardedStagingCount > 0 {
                repairAdvisory = RepairAdvisory.vaultRecoveryNotice(recovery)
            }
        } catch {
            userAlert = .recoverable(
                message: "Vault recovery failed: \(error.localizedDescription)",
                kind: .retryVaultStartupRecovery
            )
        }
    }

    func loadVault() {
        Task { @MainActor in
            workspaceGateState = .checking
            let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: repository.vaultURL)
            if case .incompatible(let report) = outcome {
                workspaceGateState = .incompatible(report)
                return
            }
            workspaceGateState = .ready
            hasDismissedVaultWelcome = VaultWelcomeDismissalStore.isDismissed(vaultURL: repository.vaultURL)

            await runStartupRecoveryIfPossible()
            await reconcileVaultState(invalidateCaches: false)
            await refreshNotes()
            await runStartupLinkGraphSync()
            selectedBaseName = nil
            selectedNoteID = nil
            activeDocument = nil
            await loadSelectedNote()
            await refreshBacklinks()
            startVaultWatcher()
        }
    }

    /// Large-vault startup policy: sync link graph inline for small/medium vaults,
    /// defer to a background task for larger vaults so note loading stays responsive.
    private func runStartupLinkGraphSync() async {
        startupLinkGraphSyncTask?.cancel()
        let relationshipCount: Int
        do {
            relationshipCount = try await repository.noteLinkRelationshipCount()
        } catch {
            userAlert = .recoverable(
                message: "Could not read relationship index for startup sync decision: \(error.localizedDescription)",
                kind: .retryStartupLinkGraphSync
            )
            return
        }
        let decision = LinkGraphStartupPolicy.decision(
            noteCount: noteSummaries.count,
            noteLinkRelationshipCount: relationshipCount,
            hardThreshold: largeVaultLinkGraphSyncThreshold,
            historicalAverageMs: loadStartupLinkGraphSyncAverageMs(),
            budgetMs: startupLinkGraphSyncBudgetMs
        )
        Logger.vault.info(
            "Startup link graph sync mode=\(String(describing: decision.mode), privacy: .public) reason=\(decision.reason, privacy: .public) notes=\(self.noteSummaries.count, privacy: .public) links=\(relationshipCount, privacy: .public)"
        )

        switch decision.mode {
        case .immediate:
            let start = Date()
            do {
                let integrity = try await repository.synchronizeLinkGraphFromRelationships()
                applyVaultIntegrityAfterLoadIfNeeded(integrity)
                recordStartupLinkGraphSyncDurationMs(Date().timeIntervalSince(start) * 1000.0)
            } catch {
                userAlert = .recoverable(
                    message: "Link index sync failed: \(error.localizedDescription)",
                    kind: .retryStartupLinkGraphSync
                )
            }
        case .deferred:
            startupLinkGraphSyncTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let start = Date()
                do {
                    let integrity = try await self.repository.synchronizeLinkGraphFromRelationships()
                    guard !Task.isCancelled else { return }
                    self.applyVaultIntegrityAfterLoadIfNeeded(integrity)
                    self.recordStartupLinkGraphSyncDurationMs(Date().timeIntervalSince(start) * 1000.0)
                    await self.refreshBacklinks()
                } catch {
                    guard !Task.isCancelled else { return }
                    self.userAlert = .recoverable(
                        message: "Deferred link index sync failed: \(error.localizedDescription)",
                        kind: .retryStartupLinkGraphSync
                    )
                }
            }
        }
    }

    private func startupLinkGraphSyncAverageKey() -> String {
        "startupLinkGraphSync.avgMs.\(repository.vaultURL.path)"
    }

    private func loadStartupLinkGraphSyncAverageMs() -> Double? {
        let key = startupLinkGraphSyncAverageKey()
        let value = UserDefaults.standard.double(forKey: key)
        guard value > 0 else { return nil }
        return value
    }

    private func recordStartupLinkGraphSyncDurationMs(_ durationMs: Double) {
        guard durationMs.isFinite, durationMs > 0 else { return }
        let key = startupLinkGraphSyncAverageKey()
        let current = loadStartupLinkGraphSyncAverageMs()
        let next: Double
        if let current {
            let alpha = min(max(startupLinkGraphSyncHistoryWeight, 0.01), 0.99)
            next = (alpha * durationMs) + ((1.0 - alpha) * current)
        } else {
            next = durationMs
        }
        UserDefaults.standard.set(next, forKey: key)
    }

    /// Canonical vault-refresh sequence for disk-driven changes: optional cache invalidation + manifest reconciliation.
    private func reconcileVaultState(invalidateCaches: Bool) async {
        if let err = await manifestRefreshFacade.reconcileAfterDiskChange(
            repository: repository,
            invalidateCaches: invalidateCaches
        ) {
            userAlert = .recoverable(
                message: err,
                kind: .retryManifestReconcileAfterDiskChange(invalidateCaches: invalidateCaches)
            )
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
            userAlert = .recoverable(
                message: "Failed to list notes: \(error.localizedDescription)",
                kind: .retryRefreshNotesAndFolderUI
            )
        }
        if workspaceGateState == .ready {
            await syncFolderSelectionAfterRefresh()
        }
    }

    private func syncFolderSelectionAfterRefresh() async {
        if let id = selectedFolderID, !isSelectedFolderStillValid() {
            selectedFolderID = pickDefaultFolderID()
        }
        // When `selectedFolderID` is nil, keep it nil: either the one-time welcome is showing
        // (`!hasDismissedVaultWelcome`) or the user cleared selection after dismissing the welcome.
    }

    private func markVaultWelcomeDismissedIfNeeded() {
        guard !hasDismissedVaultWelcome else { return }
        do {
            try VaultWelcomeDismissalStore.markDismissed(vaultURL: repository.vaultURL)
            hasDismissedVaultWelcome = true
        } catch {
            userAlert = .message(
                "Could not save workspace preferences: \(error.localizedDescription)"
            )
        }
    }

    private func isSelectedFolderStillValid() -> Bool {
        guard let id = selectedFolderID else { return false }
        switch workspaceScope {
        case .fullVault:
            if id == FolderCatalog.rootFolderID { return true }
        case .folderSubtree(let rootFolderID):
            if id == rootFolderID { return true }
        }
        return folderCatalog.folder(id: id) != nil
    }

    private func pickDefaultFolderID() -> UUID? {
        let children = topLevelFolderEntries
        if let first = children.first {
            return first.id
        }
        if hasRootLevelNotes {
            return sidebarNotesTrayFolderID
        }
        return nil
    }

    func selectFolderForPage(_ folderID: UUID?) {
        if folderID != nil {
            markVaultWelcomeDismissedIfNeeded()
        }
        selectedFolderID = folderID
        selectedBaseName = nil
        selectedNoteID = nil
        activeDocument = nil
        lastPersistedDocument = nil
        clearUndoStack()
    }

    private func applyIncompatibleWorkspaceReport(_ report: CompatibilityReport) {
        vaultWatcherSubscription = nil
        workspaceGateState = .incompatible(report)
        noteSummaries = []
        folderCatalog = FolderCatalog()
        hasDismissedVaultWelcome = false
        selectedFolderID = nil
        selectedNoteID = nil
        selectedBaseName = nil
        activeDocument = nil
        lastPersistedDocument = nil
        backlinks = []
        repairAdvisory = nil
        clearUndoStack()
        bodySearchIndexController.cancel()
        bodySearchIndex = [:]
        isBodySearchIndexBuilding = false
        backlinkRefreshScheduler.cancel()
    }

    private func scheduleBodySearchIndexRebuild() {
        bodySearchIndex = [:]
        isBodySearchIndexBuilding = true
        bodySearchIndexController.scheduleRebuild(
            repository: repository,
            apply: { [weak self] index in
                guard let self else { return }
                self.bodySearchIndex = index
                self.isBodySearchIndexBuilding = false
            },
            onFailure: { [weak self] in
                guard let self else { return }
                self.isBodySearchIndexBuilding = false
                self.userAlert = .recoverable(
                    message: "Could not update text search for this library.",
                    kind: .retryBodySearchIndex
                )
            }
        )
    }

    func performUserAlertRecovery(kind: UserAlertRecoveryKind) {
        userAlert = .none
        switch kind {
        case .retryBodySearchIndex:
            scheduleBodySearchIndexRebuild()
        case .retryVaultStartupRecovery:
            Task { await self.runStartupRecoveryIfPossible() }
        case .retryStartupLinkGraphSync:
            Task { await self.runStartupLinkGraphSync() }
        case .retryManifestReconcileAfterDiskChange(let invalidateCaches):
            Task { await self.reconcileVaultState(invalidateCaches: invalidateCaches) }
        case .retryRefreshNotesAndFolderUI:
            Task { await self.refreshNotes() }
        case .retryRefreshBacklinks:
            Task { await self.refreshBacklinks() }
        case .retryLoadActiveNote:
            Task { await self.loadSelectedNote() }
        case .retryResolveNoteSelection(let noteID):
            changeSelection(noteID: noteID)
        case .retryRefreshOnDiskFingerprints:
            Task {
                if let path = self.selectedBaseName {
                    await self.refreshOnDiskFingerprints(for: path)
                }
            }
        case .retryFlushActiveNoteToDisk:
            Task { await self.flushCurrentNoteToDiskIfDirty() }
        case .retryVaultWatcher:
            startVaultWatcher()
        case .retryProcessExternalDiskActivity:
            Task { await self.processExternalDiskActivity() }
        case .retryOpenExternalEditCompare:
            openExternalEditCompare()
        case .retryLoadViewPane(let index, let baseName):
            loadViewPane(index: index, baseName: baseName)
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

    /// Legacy outline hook: vault search is name/path-only, so body snippets are not shown.
    func searchSnippet(for _: NoteSummary) -> String? {
        nil
    }

    func createFolder(parentID: UUID = FolderCatalog.rootFolderID, name: String = "New Folder") {
        Task { @MainActor in
            do {
                let id = try await repository.createFolder(parentID: parentID, name: name)
                markVaultWelcomeDismissedIfNeeded()
                await refreshNotes()
                selectedFolderID = id
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func deleteFolder(id: UUID) {
        Task { @MainActor in
            do {
                try await repository.deleteFolder(id: id)
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
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
                    selectedNoteID = nil
                } else {
                    selectedBaseName = noteSummaries.first?.relativePath
                    selectedNoteID = noteSummaries.first?.noteID
                }
                await loadSelectedNote()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Filtered list for vault search UI: **title and relative path only** (no body matching).
    var filteredNoteSummaries: [NoteSummary] {
        let q = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return noteSummaries }
        return noteSummaries.filter { vaultNameOrPathMatches($0, queryLowercased: q) }
    }

    /// Vault-wide note rows matching ``vaultSearchQuery`` (sorted by title).
    var vaultSearchMatchingNoteSummaries: [NoteSummary] {
        let q = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return noteSummaries
            .filter { vaultNameOrPathMatches($0, queryLowercased: q) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Secondary line for vault search results (folder label and path).
    func vaultSearchResultSubtitle(for summary: NoteSummary) -> String {
        let folderLabel =
            summary.folderID == FolderCatalog.rootFolderID ? "Vault"
            : (folderCatalog.folder(id: summary.folderID)?.name ?? "Folder")
        return "\(folderLabel) — \(summary.relativePath)"
    }

    private func vaultNameOrPathMatches(_ summary: NoteSummary, queryLowercased q: String) -> Bool {
        if summary.relativePath.lowercased().contains(q) { return true }
        if summary.title.lowercased().contains(q) { return true }
        return false
    }

    func refreshBacklinks() async {
        guard let doc = activeDocument else {
            backlinks = []
            return
        }
        let targetNoteID = doc.metadata.noteID
        do {
            let graph = try await repository.loadLinkGraph()
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
            userAlert = .recoverable(
                message: "Could not refresh backlinks: \(error.localizedDescription)",
                kind: .retryRefreshBacklinks
            )
        }
    }

    private func scheduleBacklinkRefresh() {
        backlinkRefreshScheduler.schedule(delay: .milliseconds(1500)) { [weak self] in
            guard let self else { return }
            await self.refreshBacklinks()
        }
    }

    func openNote(noteID: UUID) {
        guard noteSummaries.contains(where: { $0.noteID == noteID }) else {
            userAlert = .recoverable(
                message: "Could not open note (not in vault list).",
                kind: .retryRefreshNotesAndFolderUI
            )
            return
        }
        pendingEditorScroll = nil
        changeSelection(noteID: noteID)
    }

    /// Leaves the note editor and returns to the folder page (same sidebar folder stays selected when applicable).
    func closeToFolderPage() {
        changeSelection(noteID: nil)
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
                userAlert = .recoverable(
                    message: "Rename failed: \(error.localizedDescription)",
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func createNote() {
        Task { @MainActor in
            guard let targetFolder = selectedFolderID, targetFolder != FolderCatalog.rootFolderID else {
                userAlert = .message(
                    "Select a folder in the sidebar before creating a note. New notes cannot be added at the vault root."
                )
                return
            }
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            do {
                _ = try await repository.createNote(named: "untitled-note", folderID: targetFolder)
                markVaultWelcomeDismissedIfNeeded()
                await refreshNotes()
                selectedFolderID = targetFolder
                selectedBaseName = nil
                selectedNoteID = nil
                activeDocument = nil
                lastPersistedDocument = nil
                clearUndoStack()
            } catch {
                userAlert = .recoverable(
                    message: "Failed to create note: \(error.localizedDescription)",
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func renameFolder(id: UUID, newName: String) {
        Task { @MainActor in
            _ = await renameFolderAndWait(id: id, newName: newName)
        }
    }

    /// Performs folder rename and refresh; on failure sets ``userAlert`` and returns `false`.
    @discardableResult
    func renameFolderAndWait(id: UUID, newName: String) async -> Bool {
        do {
            try await repository.renameFolder(id: id, newName: newName)
            await refreshNotes()
            return true
        } catch {
            userAlert = .recoverable(
                message: error.localizedDescription,
                kind: .retryRefreshNotesAndFolderUI
            )
            return false
        }
    }

    func deleteNoteFromFolder(noteID: UUID) {
        Task { @MainActor in
            do {
                try await repository.deleteNote(noteID: noteID)
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func loadSelectedNote() async {
        editorCursorOffset = 0
        editorTextSelection = MiranNotesCore.TextRange(start: 0, length: 0)
        if let raw = selectedBaseName {
            let resolved = await resolvedSelectionPath(from: raw)
            if resolved != raw {
                selectedBaseName = resolved
            }
        }
        guard let path = selectedBaseName else {
            pendingEditorScroll = nil
            activeDocument = nil
            selectedNoteID = nil
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
            selectedNoteID = result.document.metadata.noteID
            lastPersistedDocument = result.document
            repairAdvisory = RepairDiagnosticsBuilder.buildLoadAdvisory(result: result)
            await refreshOnDiskFingerprints(for: path)
            clearUndoStack()
            await refreshBacklinks()
        } catch {
            userAlert = .recoverable(
                message: "Failed to load note: \(error.localizedDescription)",
                kind: .retryLoadActiveNote
            )
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
            Logger.editEngine.error("Command batch truncated from \(commands.count, privacy: .public) to \(maxBatch, privacy: .public)")
            if repairAdvisory == nil {
                repairAdvisory = RepairAdvisory.commandBatchTruncated(originalCount: commands.count, appliedCap: maxBatch)
            }
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
            let name = UndoActionNaming.actionName(for: intercepted)
            let singleReplace = UndoActionNaming.isSingleReplaceTextOnly(intercepted)
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
                    let second = UndoCheckpointSupport.checkpointForRecordedStep(
                        after: after,
                        before: before,
                        intercepted: intercepted
                    )
                    undoCheckpoints = [.full(before), second]
                    undoActionNames = [name]
                    let top = 1
                    undoManager?.registerUndo(withTarget: self) { model in
                        model.applyCheckpointUndo(fromIndex: top, toIndex: top - 1)
                    }
                    undoManager?.setActionName(name)
                } else {
                    assert(materializeCheckpoint(at: undoCheckpoints.count - 1) == before)
                    let newCheckpoint = UndoCheckpointSupport.checkpointForRecordedStep(
                        after: after,
                        before: before,
                        intercepted: intercepted
                    )
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
        UndoCheckpointSupport.materialize(checkpoints: undoCheckpoints, at: index)
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

    /// Sidebar rows use ``SidebarOutlineEntry`` identities (`n:<noteID>`, `f:<folderID>`). `List(selection:)`
    /// can occasionally pass those tokens instead of the manifest ``NoteSummary/relativePath`` used in `.tag`.
    /// Valid vault paths never contain `:`, so we normalize tokens here before loading.
    private func resolvedSelectionPath(from token: String?) async -> String? {
        guard let token else { return nil }
        if token.hasPrefix("f:") {
            return nil
        }
        if token.hasPrefix("n:") {
            let rest = String(token.dropFirst(2))
            guard let id = UUID(uuidString: rest) else { return nil }
            guard let manifest = try? await repository.loadManifest() else { return nil }
            return manifest.entry(noteID: id)?.relativePath
        }
        return token
    }

    func changeSelection(baseName: String?) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        Task { @MainActor in
            let resolved = await resolvedSelectionPath(from: baseName)
            if selectedBaseName == resolved { return }
            if let p = pendingEditorScroll, let path = resolved {
                let manifest = try? await repository.loadManifest()
                let newID = manifest?.entry(relativePath: path)?.noteID
                if newID != p.noteID { pendingEditorScroll = nil }
            } else if resolved == nil {
                pendingEditorScroll = nil
            }
            await flushCurrentNoteToDiskIfDirty()
            navigationGeneration += 1
            selectedBaseName = resolved
            selectedNoteID = noteSummaries.first(where: { $0.relativePath == resolved })?.noteID
            syncActivePaneBaseName()
            await loadSelectedNote()
        }
    }

    func changeSelection(noteID: UUID?) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        selectedNoteID = noteID
        Task { @MainActor in
            let path: String?
            if let id = noteID {
                do {
                    let manifest = try await repository.loadManifest()
                    path = manifest.entry(noteID: id)?.relativePath
                } catch {
                    Logger.vault.error(
                        "loadManifest failed during note selection: \(error.localizedDescription, privacy: .public)"
                    )
                    userAlert = .recoverable(
                        message: "Could not read the note list.",
                        kind: .retryResolveNoteSelection(noteID: id)
                    )
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
            syncActivePaneBaseName()
            await loadSelectedNote()
        }
    }

    private func refreshOnDiskFingerprints(for path: String) async {
        do {
            lastKnownDiskDate = try await repository.noteModifiedDate(relativePath: path)
            lastKnownDiskRevision = try await repository.noteRevisionToken(relativePath: path)
            lastKnownNoteTextSHA256 = try await repository.noteTextFileSHA256(relativePath: path)
        } catch {
            userAlert = .recoverable(
                message: "Failed to read note on-disk state: \(error.localizedDescription)",
                kind: .retryRefreshOnDiskFingerprints
            )
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
            await refreshBacklinks()
        } catch {
            userAlert = .recoverable(
                message: "Autosave failed: \(error.localizedDescription)",
                kind: .retryFlushActiveNoteToDisk
            )
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
                let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VaultTelemetry.logAutosave(latencyMs: max(0, latencyMs))
                await self.refreshBacklinks()
            } catch {
                userAlert = .recoverable(
                    message: "Autosave failed: \(error.localizedDescription)",
                    kind: .retryFlushActiveNoteToDisk
                )
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
        await processVaultFilesystemRefreshPipeline()
    }

    /// Workspace gate, reconcile manifest after external FS churn, then deferred external-edit reconciliation.
    private func processVaultFilesystemRefreshPipeline() async {
        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: repository.vaultURL)
        if case .incompatible(let report) = outcome {
            applyIncompatibleWorkspaceReport(report)
            return
        }
        await reconcileVaultState(invalidateCaches: true)
        pendingExternalDiskCheck = true
        await runPendingExternalDiskReconciliationIfNeeded()
    }

    private func startVaultWatcher() {
        vaultWatcherSubscription = nil
        vaultWatcherSubscription = VaultWatcherHub.shared.subscribe(
            vaultURL: repository.vaultURL,
            onSetupFailed: { [weak self] error in
                self?.userAlert = .recoverable(
                    message: "Vault watch failed: \(error.localizedDescription)",
                    kind: .retryVaultWatcher
                )
            },
            onEvent: { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    await self?.processVaultFilesystemRefreshPipeline()
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
            userAlert = .recoverable(
                message: "Failed to read note timestamps: \(error.localizedDescription)",
                kind: .retryProcessExternalDiskActivity
            )
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
            userAlert = .recoverable(
                message: "Failed to read note body fingerprint: \(error.localizedDescription)",
                kind: .retryProcessExternalDiskActivity
            )
            return
        }

        let loadedFromDisk: NoteDocument
        do {
            let raw = try await repository.loadNote(baseName: path)
            loadedFromDisk = EditCommandEngine.apply(.repairMetadata, to: raw.document)
        } catch {
            userAlert = .recoverable(
                message: "Failed to read external changes: \(error.localizedDescription)",
                kind: .retryProcessExternalDiskActivity
            )
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
            Task { @MainActor in await refreshBacklinks() }
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
                userAlert = .recoverable(
                    message: "Could not load disk copy: \(error.localizedDescription)",
                    kind: .retryOpenExternalEditCompare
                )
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
                await self.handleActiveNotePresenterDidChange(noteRelativePath: path)
            }
        }
        presenter.start()
        activeNoteFilePresenter = presenter
    }

    /// `NSFilePresenter` only observes the active note `.txt`. If its body bytes still match ``lastKnownNoteTextSHA256``, skip queuing a full reconciliation (avoids churn from our own save or no-op events).
    private func handleActiveNotePresenterDidChange(noteRelativePath path: String) async {
        do {
            let h = try await repository.noteTextFileSHA256(relativePath: path)
            if let known = lastKnownNoteTextSHA256, h == known {
                return
            }
        } catch {
            Logger.vault.debug(
                "noteTextFileSHA256 failed for active presenter; queuing reconcile: \(error.localizedDescription, privacy: .public)"
            )
        }
        pendingExternalDiskCheck = true
        await runPendingExternalDiskReconciliationIfNeeded()
    }

    // MARK: - Layout management

    /// Switches to a new pane layout. Flushes the current note to disk and resizes `viewPaneStates`,
    /// preserving existing pane notes where the index still exists in the new layout.
    func setLayout(_ layout: PaneLayout) {
        Task { @MainActor in
            await flushCurrentNoteToDiskIfDirty()
            let viewPaneCount = layout.paneCount - 1
            if viewPaneStates.count > viewPaneCount {
                viewPaneStates = Array(viewPaneStates.prefix(viewPaneCount))
            } else {
                while viewPaneStates.count < viewPaneCount {
                    viewPaneStates.append(ViewPaneState())
                }
            }
            // Reset active pane to 0 when shrinking below the current index.
            if activePaneIndex >= layout.paneCount {
                activePaneIndex = 0
            }
            currentLayout = layout
        }
    }

    /// Makes `index` the editable pane. Flushes the current note, saves the active pane's note
    /// back into its slot, then loads the target pane's note into the editor.
    ///
    /// - Note: Switching active pane clears the undo history for the previous note. Acceptable for now.
    func activatePane(index: Int) {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        Task { @MainActor in
            await flushCurrentNoteToDiskIfDirty()

            // Persist what was in the active pane back into viewPaneStates before switching.
            if activePaneIndex > 0 {
                let slot = activePaneIndex - 1
                if slot < viewPaneStates.count {
                    viewPaneStates[slot].noteBaseName = selectedBaseName
                    viewPaneStates[slot].document = activeDocument
                }
            }

            activePaneIndex = index

            let targetBaseName: String?
            if index == 0 {
                // Pane 0 is always the original active slot; restore from its own tracking is handled
                // by the fact that pane 0 doesn't have a viewPaneState slot — its note is selectedBaseName.
                // When the user previously had pane 0 active, selectedBaseName is already correct.
                // When switching back to pane 0 from a higher index, we need its saved note.
                targetBaseName = selectedBaseName
            } else {
                let slot = index - 1
                targetBaseName = slot < viewPaneStates.count ? viewPaneStates[slot].noteBaseName : nil
            }

            // Undo history is intentionally cleared when switching active pane; acceptable limitation.
            changeSelection(baseName: targetBaseName)
        }
    }

    /// Loads a note for a read-only view pane asynchronously. Does not affect the active editor.
    func loadViewPane(index: Int, baseName: String) {
        guard index > 0, index < currentLayout.paneCount else { return }
        let slot = index - 1
        guard slot < viewPaneStates.count else { return }
        viewPaneStates[slot].noteBaseName = baseName
        viewPaneStates[slot].document = nil
        Task { @MainActor in
            do {
                let result = try await repository.loadNote(baseName: baseName)
                guard slot < viewPaneStates.count, viewPaneStates[slot].noteBaseName == baseName else { return }
                viewPaneStates[slot].document = result.document
            } catch {
                userAlert = .recoverable(
                    message: "Could not load view pane note: \(error.localizedDescription)",
                    kind: .retryLoadViewPane(index: index, baseName: baseName)
                )
            }
        }
    }

    /// Keeps the active pane's slot in sync whenever `selectedBaseName` changes.
    private func syncActivePaneBaseName() {
        if activePaneIndex > 0 {
            let slot = activePaneIndex - 1
            if slot < viewPaneStates.count {
                viewPaneStates[slot].noteBaseName = selectedBaseName
            }
        }
    }
}
