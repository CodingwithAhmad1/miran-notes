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
    case retryLoadNoteInPane(pane: Int, baseName: String)
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

/// Identifies a folder (and pane) waiting for the first-note body format choice.
struct FolderFirstNoteBodyPickerContext: Identifiable, Equatable, Sendable {
    var id: UUID { folderID }
    var folderID: UUID
    var pane: Int
}

@MainActor
@Observable
final class AppModel {
    /// Which editor surface and modules are active (environment / future Settings).
    var editorActivationProfile: EditorActivationProfile

    var noteSummaries: [NoteSummary] = []
    /// One session per layout tile (size == ``currentLayout/paneCount``).
    var workspacePanes: [WorkspacePaneSession] = [WorkspacePaneSession()]
    /// When set, the editor scrolls to this range once that note is loaded.
    var pendingEditorScroll: PendingEditorScroll?
    /// Raw note body text per `noteID`, built asynchronously after `refreshNotes()` for substring search.
    var bodySearchIndex: [UUID: String] = [:]
    /// True while `buildBodySearchIndex` is in flight after the latest `scheduleBodySearchIndexRebuild()` (excludes cancelled superseded work).
    var isBodySearchIndexBuilding = false
    var isLoading = false
    /// User-visible error alert (generic or with optional recovery — e.g. retry body search index).
    var userAlert: UserAlertState = .none

    var userAlertRecoveryKind: UserAlertRecoveryKind? {
        if case let .recoverable(_, kind) = userAlert { return kind }
        return nil
    }
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

    /// When true, the one-time vault welcome in the detail pane will not be shown again for this vault (see ``VaultWelcomeDismissalStore``).
    private(set) var hasDismissedVaultWelcome = false

    var topLevelFolderEntries: [FolderEntry] {
        let parent = scopeParentIDForTopLevelFolders
        return folderCatalog.childFolders(of: parent).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Top-level folders under the current scope that are not hidden from the sidebar.
    var visibleTopLevelFolderEntries: [FolderEntry] {
        topLevelFolderEntries.filter { !hiddenTopLevelFolderIDs.contains($0.id) }
    }

    /// Top-level folders under the current scope that the user hid from the sidebar (still on disk).
    var hiddenTopLevelFolderEntries: [FolderEntry] {
        topLevelFolderEntries.filter { hiddenTopLevelFolderIDs.contains($0.id) }
    }

    /// Client preference: hidden top-level folder IDs (per vault; see ``VaultHiddenFoldersStore``).
    var hiddenTopLevelFolderIDs: Set<UUID> = []

    /// When creating the first note in an empty topic folder, the user picks `.txt` vs `.md`; persisted under `.miran/`.
    private(set) var folderNoteBodyConventions: [UUID: String] = [:]

    /// Checklist rows for the vault-root “Today’s Tasks” page for ``todaysTasksSelectedDay``.
    var todaysTasksItems: [VaultTodaysTaskRow] = []

    /// Days that have on-disk task pages (sorted ascending).
    var todaysTasksKnownDays: [VaultTasksCalendarDay] = []

    /// Which calendar day’s tasks are shown and edited.
    var todaysTasksSelectedDay: VaultTasksCalendarDay

    /// Sheet context: first note in a folder with no on-disk notes and no stored body convention yet.
    var pendingFolderFirstNoteBodyPicker: FolderFirstNoteBodyPickerContext?

    /// Present the Folder Management sheet (window-local toolbar).
    var isFolderManagementPresented = false

    var scopeParentIDForTopLevelFolders: UUID {
        switch workspaceScope {
        case .fullVault:
            FolderCatalog.rootFolderID
        case .folderSubtree(let rootFolderID):
            rootFolderID
        }
    }

    var selectedFolderDisplayTitle: String {
        selectedFolderDisplayTitle(forPane: activePaneIndex)
    }

    func selectedFolderDisplayTitle(forPane pane: Int) -> String {
        guard let id = workspacePanes[pane].selectedFolderID else { return "" }
        return folderCatalog.folder(id: id)?.name ?? ""
    }

    /// Title shown in the note header and aligned with list rows (manifest-backed when available).
    var selectedNoteHeaderTitle: String {
        selectedNoteHeaderTitle(forPane: activePaneIndex)
    }

    func selectedNoteHeaderTitle(forPane pane: Int) -> String {
        if let id = workspacePanes[pane].selectedNoteID,
            let summary = noteSummaries.first(where: { $0.noteID == id }) {
            return summary.title
        }
        guard let path = workspacePanes[pane].selectedBaseName else { return "" }
        return VaultPath.displayTitle(forRelativePath: path)
    }

    var folderPageNoteSummaries: [NoteSummary] {
        folderPageNoteSummaries(forPane: activePaneIndex)
    }

    func folderPageNoteSummaries(forPane pane: Int) -> [NoteSummary] {
        guard let id = workspacePanes[pane].selectedFolderID else { return [] }
        return noteSummaries.filter { $0.folderID == id }
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
        allowsToolbarNewNote(forPane: activePaneIndex)
    }

    func allowsToolbarNewNote(forPane pane: Int) -> Bool {
        guard let id = workspacePanes[pane].selectedFolderID else { return false }
        guard id != FolderCatalog.rootFolderID else { return false }
        return folderCatalog.allowsNotes(in: id)
    }

    /// Role for non-root folders; `nil` means the user has not classified the folder yet.
    func performNewFolderFromShortcut() {
        guard ensureWorkspaceReadyForVaultShortcuts() else { return }
        createFolder()
    }

    /// Menu / keyboard entry point for new note; gates on workspace readiness, then delegates to ``createNote()`` (including folder selection rules).
    func performNewNoteFromShortcut() {
        guard ensureWorkspaceReadyForVaultShortcuts() else { return }
        createNote()
    }

    private func ensureWorkspaceReadyForVaultShortcuts() -> Bool {
        switch workspaceGateState {
        case .ready:
            return true
        case .checking:
            userAlert = .message(
                String(localized: "The workspace is still loading. Try again in a moment.")
            )
            return false
        case .incompatible:
            userAlert = .message(
                String(localized: "This workspace isn’t available. Choose another folder or resolve compatibility issues before creating items.")
            )
            return false
        }
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
    /// Index of the pane that receives toolbar search, back affordances, and primary editing focus.
    var activePaneIndex: Int = 0

    /// Limits sidebar/navigation to a folder subtree when not ``WorkspaceScope/fullVault``.
    var workspaceScope: WorkspaceScope = .fullVault

    let repository: NoteRepository
    private let manifestRefreshFacade = VaultManifestRefreshFacade()
    let bodySearchIndexController = NoteBodySearchIndexController()
    let backlinkRefreshScheduler = DebouncedAsyncWorkScheduler()
    /// In-flight debounced autosave tasks keyed by pane index.
    var saveTasks: [Int: Task<Void, Never>] = [:]
    var todaysTasksPersistTask: Task<Void, Never>?
    /// Pinned notes (vault UI state; see ``VaultUIStateStore``).
    var pinnedNoteIDs: [UUID] = []
    /// Recently opened notes, most recent first (vault UI state; persisted debounced).
    var recentNoteIDs: [UUID] = []
    var recentsPersistTask: Task<Void, Never>?
    /// Quick-open palette state (⌘P overlay).
    let quickOpen = QuickOpenModel()
    /// Icon-browser positions per folder (cache over `.miran/ui-state/icon-layout/`).
    var folderIconLayoutCache: [UUID: [UUID: CGPoint]] = [:]
    /// Trashed notes shown in the Trash sheet (refreshed on trash operations and sheet open).
    var trashedNotes: [TrashedNoteSummary] = []
    /// Parsed `properties["tags"]` per note (built with the body search index; patched on save).
    var tagIndex: [UUID: Set<String>] = [:]
    /// Presents the Trash sheet.
    var isTrashPresented = false
    /// Per-folder icons/list choice (raw ``FolderPageViewMode``; cache over `folder-view-modes.json`).
    var folderViewModes: [UUID: String] = [:]
    var vaultWatcherSubscription: VaultWatcherSubscription?
    /// Set when the vault watcher fires; processed after autosave finishes so events are not dropped.
    var pendingExternalDiskCheck = false
    var undoManager: UndoManager?
    private let undoPolicy: UndoPolicy
    /// Pane index used by window-level bindings (toolbar, menu); always in range of ``workspacePanes``.
    var keyPaneIndex: Int {
        guard !workspacePanes.isEmpty else { return 0 }
        return min(max(0, activePaneIndex), workspacePanes.count - 1)
    }

    /// Action names for each undo step on the **active** pane (internal for tests).
    var undoHistory: [String] { workspacePanes[keyPaneIndex].undoActionNames }
    /// Approximate retained undo state for diagnostics / `swift test` (active pane).
    var undoRetentionMemoryEstimateBytes: Int {
        let kp = keyPaneIndex
        let cps = workspacePanes[kp].undoCheckpoints
        return cps.enumerated().reduce(0) { sum, entry in
            let (i, cp) = entry
            let mat = materializeCheckpoint(forPane: kp, at: i)
            let cmdOverhead: Int
            if case let .replaceTextOnly(forward, undo) = cp {
                cmdOverhead = (forward.count + undo.count) * 64
            } else {
                cmdOverhead = 0
            }
            return sum + mat.estimatedUndoMemoryBytes + cmdOverhead
        }
    }

    // MARK: - Active pane convenience (toolbar & tests; indexes ``activePaneIndex``)

    var selectedFolderID: UUID? {
        get { workspacePanes[keyPaneIndex].selectedFolderID }
        set { workspacePanes[keyPaneIndex].selectedFolderID = newValue }
    }

    var selectedNoteID: UUID? {
        get { workspacePanes[keyPaneIndex].selectedNoteID }
        set { workspacePanes[keyPaneIndex].selectedNoteID = newValue }
    }

    var selectedBaseName: String? {
        get { workspacePanes[keyPaneIndex].selectedBaseName }
        set { workspacePanes[keyPaneIndex].selectedBaseName = newValue }
    }

    var activeDocument: NoteDocument? {
        get { workspacePanes[keyPaneIndex].activeDocument }
        set { workspacePanes[keyPaneIndex].activeDocument = newValue }
    }

    var vaultSearchQuery: String {
        get { workspacePanes[keyPaneIndex].vaultSearchQuery }
        set { workspacePanes[keyPaneIndex].vaultSearchQuery = newValue }
    }

    var editorFindQuery: String {
        get { workspacePanes[keyPaneIndex].editorFindQuery }
        set { workspacePanes[keyPaneIndex].editorFindQuery = newValue }
    }

    var editorCursorOffset: Int {
        get { workspacePanes[keyPaneIndex].editorCursorOffset }
        set { workspacePanes[keyPaneIndex].editorCursorOffset = newValue }
    }

    var editorTextSelection: MiranNotesCore.TextRange {
        get { workspacePanes[keyPaneIndex].editorTextSelection }
        set { workspacePanes[keyPaneIndex].editorTextSelection = newValue }
    }

    var repairAdvisory: RepairAdvisory? {
        get { workspacePanes[keyPaneIndex].repairAdvisory }
        set { workspacePanes[keyPaneIndex].repairAdvisory = newValue }
    }

    var backlinks: [BacklinkItem] {
        get { workspacePanes[keyPaneIndex].backlinks }
        set { workspacePanes[keyPaneIndex].backlinks = newValue }
    }
    private let commandPipelineContract: CommandPipelineContract
    /// Public registration API for typed extensions; runs before ``localCommandInterceptors`` (see `ExtensionRegistry` docs).
    let extensionRegistry = ExtensionRegistry()
    private var localCommandInterceptors: [UUID: ([EditCommand], NoteDocument, CommandContext) -> [EditCommand]] = [:]
    /// Insertion-ordered list of interceptor keys, so interceptors fire in registration order.
    private var localCommandInterceptorOrder: [UUID] = []

    let autosaveDebounceMilliseconds: UInt64
    private let largeVaultLinkGraphSyncThreshold: Int
    private let startupLinkGraphSyncBudgetMs: Double
    private let startupLinkGraphSyncHistoryWeight: Double
    private var startupLinkGraphSyncTask: Task<Void, Never>?
    var activeNoteFilePresenter: ActiveNoteFilePresenter?

    /// Canonical default note ordering (A→Z by title, then path for stable ties).
    private static func noteSummarySortPredicate(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
    }

    init(
        repository: NoteRepository,
        workspaceScope: WorkspaceScope = .fullVault,
        autosaveDebounceMilliseconds: UInt64 = 400,
        undoPolicy: UndoPolicy = .defaultPolicy,
        largeVaultLinkGraphSyncThreshold: Int = 2_000,
        startupLinkGraphSyncBudgetMs: Double = 120,
        startupLinkGraphSyncHistoryWeight: Double = 0.3,
        commandPipelineContract: CommandPipelineContract = CommandPipelineContract(),
        editorActivationProfile: EditorActivationProfile = .resolvedFromEnvironment()
    ) {
        self.editorActivationProfile = editorActivationProfile
        self.repository = repository
        self.workspaceScope = workspaceScope
        self.autosaveDebounceMilliseconds = autosaveDebounceMilliseconds
        self.undoPolicy = undoPolicy
        self.largeVaultLinkGraphSyncThreshold = largeVaultLinkGraphSyncThreshold
        self.startupLinkGraphSyncBudgetMs = startupLinkGraphSyncBudgetMs
        self.startupLinkGraphSyncHistoryWeight = startupLinkGraphSyncHistoryWeight
        self.commandPipelineContract = commandPipelineContract
        self.todaysTasksSelectedDay = VaultTasksCalendarDay.today(calendar: Self.vaultTasksCalendar())
        VaultSecurityScopeCoordinator.shared.retain(repository.vaultURL)
    }

    static func vaultTasksCalendar() -> Calendar {
        var c = Calendar.autoupdatingCurrent
        c.timeZone = TimeZone.current
        return c
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

    /// Ensures ``workspacePanes`` count matches ``currentLayout/paneCount``.
    func ensureWorkspacePaneCount() {
        let n = currentLayout.paneCount
        if workspacePanes.count > n {
            activePaneIndex = min(max(0, activePaneIndex), max(0, n - 1))
            workspacePanes = Array(workspacePanes.prefix(n))
        }
        while workspacePanes.count < n {
            workspacePanes.append(WorkspacePaneSession())
        }
        if activePaneIndex >= workspacePanes.count {
            activePaneIndex = max(0, workspacePanes.count - 1)
        }
    }

    private func materializeCheckpoint(forPane pane: Int, at index: Int) -> NoteDocument {
        UndoCheckpointSupport.materialize(checkpoints: workspacePanes[pane].undoCheckpoints, at: index)
    }

    private func runStartupRecoveryIfPossible() async {
        do {
            let recovery = try await repository.performStartupRecovery()
            if recovery.resumedAndCompletedCount > 0 || recovery.discardedStagingCount > 0 {
                workspacePanes[0].repairAdvisory = RepairAdvisory.vaultRecoveryNotice(recovery)
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
            todaysTasksPersistTask?.cancel()
            todaysTasksPersistTask = nil
            todaysTasksItems = []
            todaysTasksKnownDays = []
            workspaceGateState = .checking
            let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: repository.vaultURL)
            if case .incompatible(let report) = outcome {
                workspaceGateState = .incompatible(report)
                return
            }
            workspaceGateState = .ready
            hasDismissedVaultWelcome = VaultWelcomeDismissalStore.isDismissed(vaultURL: repository.vaultURL)
            hiddenTopLevelFolderIDs = VaultHiddenFoldersStore.load(vaultURL: repository.vaultURL)
            folderNoteBodyConventions = FolderNoteBodyConventionStore.load(vaultURL: repository.vaultURL)
            loadPinsAndRecents()
            loadFolderViewModes()
            do {
                try loadVaultTodaysTasksStateAfterPreferences()
            } catch {
                userAlert = .message("Could not load Today’s Tasks: \(error.localizedDescription)")
            }
            pendingFolderFirstNoteBodyPicker = nil

            await runStartupRecoveryIfPossible()
            await reconcileVaultState(invalidateCaches: false)
            await refreshNotes()
            await runStartupLinkGraphSync()
            currentLayout = .single
            activePaneIndex = 0
            workspacePanes = [WorkspacePaneSession()]
            await loadSelectedNote(pane: 0)
            await refreshBacklinks(forPane: activePaneIndex)
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
    /// - Parameter refreshNotesOnSuccess: When true (e.g. vault watcher), refreshes sidebar/search summaries after a successful reconcile so externally added `.md` / `.txt` files appear without a manual reload.
    func reconcileVaultState(invalidateCaches: Bool, refreshNotesOnSuccess: Bool = false) async {
        if let err = await manifestRefreshFacade.reconcileAfterDiskChange(
            repository: repository,
            invalidateCaches: invalidateCaches
        ) {
            userAlert = .recoverable(
                message: err,
                kind: .retryManifestReconcileAfterDiskChange(invalidateCaches: invalidateCaches)
            )
            return
        }
        if refreshNotesOnSuccess {
            await refreshNotes()
        }
    }

    private func applyVaultIntegrityAfterLoadIfNeeded(_ result: VaultIntegrityResult) {
        guard !result.isClean else { return }
        guard !workspacePanes.contains(where: { $0.repairAdvisory != nil }) else { return }
        workspacePanes[0].repairAdvisory = RepairAdvisory.vaultIntegrityNotice(result)
    }

    private func applyVaultIntegrityAfterSave(_ result: VaultIntegrityResult) {
        guard !result.isClean else { return }
        let kp = keyPaneIndex
        if workspacePanes.indices.contains(kp) {
            workspacePanes[kp].repairAdvisory = RepairAdvisory.vaultIntegrityNotice(result)
        }
    }

    func toggleMarkdownPreview(pane: Int) {
        guard workspacePanes.indices.contains(pane) else { return }
        workspacePanes[pane].showMarkdownPreview.toggle()
    }

    func refreshNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            noteSummaries = try await repository.listNotes().sorted(by: Self.noteSummarySortPredicate)
            var catalog = try await repository.loadFolderCatalog()
            catalog.ensureRoot()
            if catalog.isDirty {
                try await repository.persistFolderCatalog(catalog)
                catalog.isDirty = false
            }
            folderCatalog = catalog
            scheduleBodySearchIndexRebuild()
        } catch {
            userAlert = .recoverable(
                message: "Failed to list notes: \(error.localizedDescription)",
                kind: .retryRefreshNotesAndFolderUI
            )
        }
        if workspaceGateState == .ready {
            reconcileHiddenFoldersWithCatalogIfNeeded()
            await syncFolderSelectionAfterRefresh()
        }
    }
    private func syncFolderSelectionAfterRefresh() async {
        for i in workspacePanes.indices {
            if let id = workspacePanes[i].selectedFolderID, !isSelectedFolderStillValid(id) {
                workspacePanes[i].selectedFolderID = pickDefaultFolderID()
            }
        }
        // When `selectedFolderID` is nil, keep it nil: either the one-time welcome is showing
        // (`!hasDismissedVaultWelcome`) or the user cleared selection after dismissing the welcome.
    }

    func markVaultWelcomeDismissedIfNeeded() {
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

    private func isSelectedFolderStillValid(_ id: UUID) -> Bool {
        switch workspaceScope {
        case .fullVault:
            if id == FolderCatalog.rootFolderID { return true }
        case .folderSubtree(let rootFolderID):
            if id == rootFolderID { return true }
        }
        guard folderCatalog.folder(id: id) != nil else { return false }
        if hiddenTopLevelFolderIDs.contains(id) { return false }
        return true
    }

    func pickDefaultFolderID() -> UUID? {
        let children = visibleTopLevelFolderEntries
        if let first = children.first {
            return first.id
        }
        if hasRootLevelNotes {
            return sidebarNotesTrayFolderID
        }
        return nil
    }

    func selectFolderForPage(_ folderID: UUID?, pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(p) else { return }
        if folderID != nil {
            markVaultWelcomeDismissedIfNeeded()
        }
        workspacePanes[p].selectedFolderID = folderID
        workspacePanes[p].selectedBaseName = nil
        workspacePanes[p].selectedNoteID = nil
        workspacePanes[p].activeDocument = nil
        workspacePanes[p].lastPersistedDocument = nil
        clearUndoStack(forPane: p)
    }

    func applyIncompatibleWorkspaceReport(_ report: CompatibilityReport) {
        vaultWatcherSubscription = nil
        workspaceGateState = .incompatible(report)
        noteSummaries = []
        folderCatalog = FolderCatalog()
        hasDismissedVaultWelcome = false
        workspacePanes = [WorkspacePaneSession()]
        activePaneIndex = 0
        currentLayout = .single
        isFolderManagementPresented = false
        clearUndoStack(forPane: 0)
        bodySearchIndexController.cancel()
        bodySearchIndex = [:]
        isBodySearchIndexBuilding = false
        backlinkRefreshScheduler.cancel()
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
            Task { await self.reconcileVaultState(invalidateCaches: invalidateCaches, refreshNotesOnSuccess: true) }
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
                let p = self.activePaneIndex
                guard self.workspacePanes.indices.contains(p),
                    let path = self.workspacePanes[p].selectedBaseName else { return }
                await self.refreshOnDiskFingerprints(for: path, pane: p)
            }
        case .retryFlushActiveNoteToDisk:
            Task { await self.flushCurrentNoteToDiskIfDirty() }
        case .retryVaultWatcher:
            startVaultWatcher()
        case .retryProcessExternalDiskActivity:
            Task { await self.processExternalDiskActivity() }
        case .retryOpenExternalEditCompare:
            openExternalEditCompare()
        case .retryLoadNoteInPane(let pane, let baseName):
            Task { @MainActor in
                await self.reloadNoteInPane(pane: pane, baseName: baseName)
            }
        }
    }

    /// Legacy outline hook: vault search is name/path-only, so body snippets are not shown.
    func deleteSelectedNote(pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard let path = workspacePanes[pane].selectedBaseName else { return }
        Task { @MainActor in
            do {
                let manifest = try await repository.loadManifest()
                guard let id = manifest.entry(relativePath: path)?.noteID else { return }
                try await repository.trashNote(noteID: id)
                refreshTrashedNotes()
                await refreshNotes()
                if noteSummaries.isEmpty {
                    self.workspacePanes[pane].selectedBaseName = nil
                    self.workspacePanes[pane].selectedNoteID = nil
                } else {
                    self.workspacePanes[pane].selectedBaseName = noteSummaries.first?.relativePath
                    self.workspacePanes[pane].selectedNoteID = noteSummaries.first?.noteID
                }
                for i in self.workspacePanes.indices where i != pane {
                    if self.workspacePanes[i].selectedNoteID == id {
                        self.workspacePanes[i].selectedBaseName = nil
                        self.workspacePanes[i].selectedNoteID = nil
                        self.workspacePanes[i].activeDocument = nil
                        self.workspacePanes[i].lastPersistedDocument = nil
                        self.clearUndoStack(forPane: i)
                    }
                }
                await loadSelectedNote(pane: pane)
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Filtered list for vault search UI: **title and relative path only** (no body matching).
    func openNote(noteID: UUID, pane: Int? = nil) {
        guard noteSummaries.contains(where: { $0.noteID == noteID }) else {
            userAlert = .recoverable(
                message: "Could not open note (not in vault list).",
                kind: .retryRefreshNotesAndFolderUI
            )
            return
        }
        pendingEditorScroll = nil
        changeSelection(noteID: noteID, pane: pane ?? activePaneIndex)
    }

    /// Leaves the note editor and returns to the folder page (same sidebar folder stays selected when applicable).
    func closeToFolderPage(pane: Int? = nil) {
        changeSelection(noteID: nil, pane: pane ?? activePaneIndex)
    }
    func clearPendingEditorScroll() {
        pendingEditorScroll = nil
    }

    func renameActiveNote(newTitle: String, pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard let oldPath = workspacePanes[pane].selectedBaseName else { return }
        Task { @MainActor in
            await flushPaneIfDirty(pane)
            self.workspacePanes[pane].navigationGeneration += 1
            do {
                let newPath = try await repository.renameNote(from: oldPath, to: newTitle)
                await refreshNotes()
                self.workspacePanes[pane].selectedBaseName = newPath
                await refreshBacklinks(forPane: pane)
            } catch {
                userAlert = .recoverable(
                    message: "Rename failed: \(error.localizedDescription)",
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func createNote(pane: Int? = nil) {
        Task { @MainActor in
            let pane = pane ?? activePaneIndex
            guard let targetFolder = workspacePanes[pane].selectedFolderID, targetFolder != FolderCatalog.rootFolderID else {
                userAlert = .message(
                    "Select a folder in the sidebar before creating a note. New notes cannot be added at the vault root."
                )
                return
            }
            guard folderCatalog.allowsNotes(in: targetFolder) else {
                userAlert = .message(
                    "Notes can only be created in a Repository folder (or after you finish classifying this folder). Dashboard folders hold nested folders only."
                )
                return
            }
            guard let bodyExt = resolvedBodyExtensionForNewNote(in: targetFolder) else {
                pendingFolderFirstNoteBodyPicker = FolderFirstNoteBodyPickerContext(folderID: targetFolder, pane: pane)
                return
            }
            await finishCreateNote(pane: pane, folderID: targetFolder, bodyFileExtension: bodyExt)
        }
    }

    /// Completes a new note after the first-note body-format sheet returns.
    func confirmPendingFirstNoteBodyFormat(bodyFileExtension: String) {
        guard let ctx = pendingFolderFirstNoteBodyPicker else { return }
        pendingFolderFirstNoteBodyPicker = nil
        let norm = PathIndexEntry.normalizeBodyFileExtension(bodyFileExtension)
        Task { @MainActor in
            do {
                try persistFolderNoteBodyConvention(folderID: ctx.folderID, bodyFileExtension: norm)
            } catch {
                userAlert = .message("Could not save note format preference: \(error.localizedDescription)")
                return
            }
            await finishCreateNote(pane: ctx.pane, folderID: ctx.folderID, bodyFileExtension: norm)
        }
    }

    func cancelPendingFirstNoteBodyPicker() {
        pendingFolderFirstNoteBodyPicker = nil
    }

    /// Per-pane editor profile from the open note’s on-disk body, with `MIRAN_EDITOR_KIND` as a global override.
    func effectiveEditorActivationProfile(forPane pane: Int) -> EditorActivationProfile {
        if let raw = ProcessInfo.processInfo.environment["MIRAN_EDITOR_KIND"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return EditorActivationProfile.resolve(kindRaw: raw)
        }
        guard workspacePanes.indices.contains(pane),
              let noteID = workspacePanes[pane].selectedNoteID,
              let summary = noteSummaries.first(where: { $0.noteID == noteID })
        else {
            return editorActivationProfile
        }
        let kind: EditorKind = summary.bodyFileExtension == "md" ? .plainMarkdownSource : .blockNative
        return EditorActivationProfile(editorKind: kind, modules: editorActivationProfile.modules)
    }

    func resolvedBodyExtensionForNewNote(in folderID: UUID) -> String? {
        let inFolder = noteSummaries.filter { $0.folderID == folderID }
        if let first = inFolder.first {
            return first.bodyFileExtension
        }
        if let stored = folderNoteBodyConventions[folderID] {
            return PathIndexEntry.normalizeBodyFileExtension(stored)
        }
        return nil
    }

    private func persistFolderNoteBodyConvention(folderID: UUID, bodyFileExtension: String) throws {
        let norm = PathIndexEntry.normalizeBodyFileExtension(bodyFileExtension)
        folderNoteBodyConventions[folderID] = norm
        try FolderNoteBodyConventionStore.save(folderNoteBodyConventions, vaultURL: repository.vaultURL)
    }

    private func finishCreateNote(pane: Int, folderID: UUID, bodyFileExtension: String) async {
        await flushPaneIfDirty(pane)
        workspacePanes[pane].navigationGeneration += 1
        do {
            _ = try await repository.createNote(
                named: "untitled-note",
                folderID: folderID,
                bodyFileExtension: bodyFileExtension
            )
            markVaultWelcomeDismissedIfNeeded()
            await refreshNotes()
            workspacePanes[pane].selectedFolderID = folderID
            workspacePanes[pane].selectedBaseName = nil
            workspacePanes[pane].selectedNoteID = nil
            workspacePanes[pane].activeDocument = nil
            workspacePanes[pane].lastPersistedDocument = nil
            clearUndoStack(forPane: pane)
        } catch {
            userAlert = .recoverable(
                message: "Failed to create note: \(error.localizedDescription)",
                kind: .retryRefreshNotesAndFolderUI
            )
        }
    }

    func resolvedBodyFileExtensionForSelectedNote(pane: Int) -> String {
        guard workspacePanes.indices.contains(pane),
              let noteID = workspacePanes[pane].selectedNoteID,
              let summary = noteSummaries.first(where: { $0.noteID == noteID })
        else {
            return "txt"
        }
        return summary.bodyFileExtension
    }
    func deleteNoteFromFolder(noteID: UUID) {
        Task { @MainActor in
            do {
                try await repository.trashNote(noteID: noteID)
                refreshTrashedNotes()
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
        await loadSelectedNote(pane: activePaneIndex)
    }

    func loadSelectedNote(pane: Int) async {
        guard workspacePanes.indices.contains(pane) else { return }
        workspacePanes[pane].editorCursorOffset = 0
        workspacePanes[pane].editorTextSelection = MiranNotesCore.TextRange(start: 0, length: 0)
        if let raw = workspacePanes[pane].selectedBaseName {
            let resolved = await resolvedSelectionPath(from: raw)
            if resolved != raw {
                workspacePanes[pane].selectedBaseName = resolved
            }
        }
        guard let path = workspacePanes[pane].selectedBaseName else {
            pendingEditorScroll = nil
            workspacePanes[pane].activeDocument = nil
            workspacePanes[pane].selectedNoteID = nil
            workspacePanes[pane].lastPersistedDocument = nil
            workspacePanes[pane].lastKnownDiskDate = nil
            workspacePanes[pane].lastKnownDiskRevision = nil
            workspacePanes[pane].lastKnownNoteTextSHA256 = nil
            workspacePanes[pane].repairAdvisory = nil
            workspacePanes[pane].backlinks = []
            clearUndoStack(forPane: pane)
            if pane == activePaneIndex {
                updateActiveNoteFilePresenter()
            }
            return
        }
        do {
            let result = try await repository.loadNote(baseName: path)
            workspacePanes[pane].activeDocument = result.document
            workspacePanes[pane].selectedNoteID = result.document.metadata.noteID
            workspacePanes[pane].lastPersistedDocument = result.document
            workspacePanes[pane].repairAdvisory = RepairDiagnosticsBuilder.buildLoadAdvisory(result: result)
            await refreshOnDiskFingerprints(for: path, pane: pane)
            clearUndoStack(forPane: pane)
            await refreshBacklinks(forPane: pane)
        } catch {
            userAlert = .recoverable(
                message: "Failed to load note: \(error.localizedDescription)",
                kind: .retryLoadActiveNote
            )
        }
        if pane == activePaneIndex {
            updateActiveNoteFilePresenter()
        }
    }

    private func reloadNoteInPane(pane: Int, baseName: String) async {
        guard workspacePanes.indices.contains(pane) else { return }
        workspacePanes[pane].selectedBaseName = baseName
        await loadSelectedNote(pane: pane)
    }

    func dismissRepairAdvisory(pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(p) else { return }
        workspacePanes[p].repairAdvisory = nil
    }

    func presentFullBufferAdvisory(pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(p) else { return }
        workspacePanes[p].repairAdvisory = RepairAdvisory(
            kind: .fullBufferFallback,
            title: "We updated how this note is structured",
            explanation:
                "A large edit happened in one step, so section information may differ slightly from before. What you see on screen is unchanged.",
            detailsPlainText: RepairAdvisory.fullBufferDetails
        )
    }

    func presentSizeLimitAdvisory(pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(p) else { return }
        workspacePanes[p].repairAdvisory = RepairAdvisory(
            kind: .sizeLimitExceeded,
            title: "This note can't grow further",
            explanation: "This note is at the maximum size, so the new text was not added.",
            detailsPlainText: RepairAdvisory.sizeLimitDetails
        )
    }

    func revealSelectedNoteFileInFinder(pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        guard let path = workspacePanes[p].selectedBaseName else { return }
        let ext = resolvedBodyFileExtensionForSelectedNote(pane: p)
        let url = VaultPath.fileURL(vaultRoot: repository.vaultURL, relativePathWithoutExtension: path, extension: ext)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealSelectedNoteFileInFinder() {
        revealSelectedNoteFileInFinder(pane: activePaneIndex)
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
            let kp = keyPaneIndex
            if workspacePanes[kp].repairAdvisory == nil {
                workspacePanes[kp].repairAdvisory = RepairAdvisory.commandBatchTruncated(
                    originalCount: commands.count,
                    appliedCap: maxBatch
                )
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
            let undoPane = activePaneIndex
            let after = doc
            let name = UndoActionNaming.actionName(for: intercepted)
            let singleReplace = UndoActionNaming.isSingleReplaceTextOnly(intercepted)
            let now = Date()
            let windowSeconds = Double(undoPolicy.coalesceReplaceTextWindowNanoseconds) / 1_000_000_000.0

            let cps = workspacePanes[undoPane].undoCheckpoints
            let lastMatchesBefore =
                !cps.isEmpty
                && materializeCheckpoint(forPane: undoPane, at: cps.count - 1) == before

            let canTryCoalesce =
                undoPolicy.coalesceReplaceTextWindowNanoseconds > 0
                && singleReplace
                && workspacePanes[undoPane].lastRecordedUndoWasSingleReplaceText
                && lastMatchesBefore

            var didCoalesce = false
            if canTryCoalesce, let lastDate = workspacePanes[undoPane].lastUndoRegistrationDate {
                let elapsed = now.timeIntervalSince(lastDate)
                if elapsed < windowSeconds {
                    let lastIdx = workspacePanes[undoPane].undoCheckpoints.count - 1
                    let beforeIdx = lastIdx - 1
                    let docBeforeStep = materializeCheckpoint(forPane: undoPane, at: beforeIdx)
                    switch workspacePanes[undoPane].undoCheckpoints[lastIdx] {
                    case .replaceTextOnly(let forward, _):
                        let combined = forward + intercepted
                        if let rebuilt = UndoInverseSupport.replaceTextChainUndoCommands(forward: combined, documentBefore: docBeforeStep),
                           rebuilt.after == after {
                            workspacePanes[undoPane].undoCheckpoints[lastIdx] = .replaceTextOnly(
                                forward: combined,
                                undoCommands: rebuilt.undoCommands
                            )
                        } else {
                            workspacePanes[undoPane].undoCheckpoints[lastIdx] = .full(after)
                        }
                    case .full:
                        workspacePanes[undoPane].undoCheckpoints[lastIdx] = .full(after)
                    }
                    if !workspacePanes[undoPane].undoActionNames.isEmpty {
                        workspacePanes[undoPane].undoActionNames[workspacePanes[undoPane].undoActionNames.count - 1] = name
                    }
                    reregisterAllUndoActions(forPane: undoPane)
                    didCoalesce = true
                }
            }

            if !didCoalesce {
                if workspacePanes[undoPane].undoCheckpoints.isEmpty {
                    let second = UndoCheckpointSupport.checkpointForRecordedStep(
                        after: after,
                        before: before,
                        intercepted: intercepted
                    )
                    workspacePanes[undoPane].undoCheckpoints = [.full(before), second]
                    workspacePanes[undoPane].undoActionNames = [name]
                    let top = 1
                    let capturedPane = undoPane
                    undoManager?.registerUndo(withTarget: self) { model in
                        model.applyCheckpointUndo(fromIndex: top, toIndex: top - 1, pane: capturedPane)
                    }
                    undoManager?.setActionName(name)
                } else {
                    assert(materializeCheckpoint(forPane: undoPane, at: workspacePanes[undoPane].undoCheckpoints.count - 1) == before)
                    let newCheckpoint = UndoCheckpointSupport.checkpointForRecordedStep(
                        after: after,
                        before: before,
                        intercepted: intercepted
                    )
                    workspacePanes[undoPane].undoCheckpoints.append(newCheckpoint)
                    workspacePanes[undoPane].undoActionNames.append(name)
                    let top = workspacePanes[undoPane].undoCheckpoints.count - 1
                    let capturedPane = undoPane
                    undoManager?.registerUndo(withTarget: self) { model in
                        model.applyCheckpointUndo(fromIndex: top, toIndex: top - 1, pane: capturedPane)
                    }
                    undoManager?.setActionName(name)
                }
            }

            workspacePanes[undoPane].lastRecordedUndoWasSingleReplaceText = singleReplace
            workspacePanes[undoPane].lastUndoRegistrationDate = now
            enforceUndoPolicyIfNeeded(forPane: undoPane)
        }

        activeDocument = doc
        scheduleAutosave(forPane: activePaneIndex)
        scheduleBacklinkRefresh(forPane: activePaneIndex)
        return doc
    }

    private func applyCheckpointUndo(fromIndex: Int, toIndex: Int, pane: Int) {
        guard workspacePanes[pane].undoCheckpoints.indices.contains(toIndex) else { return }
        workspacePanes[pane].activeDocument = materializeCheckpoint(forPane: pane, at: toIndex)
        scheduleAutosave(forPane: pane)
        scheduleBacklinkRefresh(forPane: pane)
        undoManager?.registerUndo(withTarget: self) { model in
            model.applyCheckpointUndo(fromIndex: toIndex, toIndex: fromIndex, pane: pane)
        }
    }

    func reregisterAllUndoActions(forPane pane: Int) {
        undoManager?.removeAllActions(withTarget: self)
        let cps = workspacePanes[pane].undoCheckpoints
        guard cps.count >= 2 else { return }
        for i in 1..<cps.count {
            let fromIdx = i
            let toIdx = i - 1
            let name = workspacePanes[pane].undoActionNames[i - 1]
            let capturedPane = pane
            undoManager?.registerUndo(withTarget: self) { model in
                model.applyCheckpointUndo(fromIndex: fromIdx, toIndex: toIdx, pane: capturedPane)
            }
            undoManager?.setActionName(name)
        }
    }

    func clearUndoStack(forPane pane: Int) {
        undoManager?.removeAllActions(withTarget: self)
        workspacePanes[pane].undoCheckpoints.removeAll()
        workspacePanes[pane].undoActionNames.removeAll()
        workspacePanes[pane].lastUndoRegistrationDate = nil
        workspacePanes[pane].lastRecordedUndoWasSingleReplaceText = false
    }

    private func enforceUndoPolicyIfNeeded(forPane pane: Int) {
        let max = undoPolicy.maxUndoSteps
        let steps = workspacePanes[pane].undoCheckpoints.count - 1
        guard steps > max else { return }
        let dropCount = steps - max
        let newCheckpoints: [UndoCheckpoint] = (dropCount..<workspacePanes[pane].undoCheckpoints.count).map { i in
            .full(materializeCheckpoint(forPane: pane, at: i))
        }
        workspacePanes[pane].undoCheckpoints = newCheckpoints
        workspacePanes[pane].undoActionNames = Array(workspacePanes[pane].undoActionNames.suffix(max))
        reregisterAllUndoActions(forPane: pane)
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
        changeSelection(baseName: baseName, pane: activePaneIndex)
    }

    func changeSelection(baseName: String?, pane: Int) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        Task { @MainActor in
            guard self.workspacePanes.indices.contains(pane) else { return }
            let resolved = await resolvedSelectionPath(from: baseName)
            if self.workspacePanes[pane].selectedBaseName == resolved { return }
            if let p = pendingEditorScroll, let path = resolved {
                let manifest = try? await repository.loadManifest()
                let newID = manifest?.entry(relativePath: path)?.noteID
                if newID != p.noteID { pendingEditorScroll = nil }
            } else if resolved == nil {
                pendingEditorScroll = nil
            }
            await flushPaneIfDirty(pane)
            self.workspacePanes[pane].navigationGeneration += 1
            self.workspacePanes[pane].selectedBaseName = resolved
            self.workspacePanes[pane].selectedNoteID =
                noteSummaries.first(where: { $0.relativePath == resolved })?.noteID
            await loadSelectedNote(pane: pane)
        }
    }

    func changeSelection(noteID: UUID?) {
        changeSelection(noteID: noteID, pane: activePaneIndex)
    }

    func changeSelection(noteID: UUID?, pane: Int) {
        externalEditConflictAlert = nil
        diskActivityBanner = nil
        externalTextCompare = nil
        Task { @MainActor in
            guard self.workspacePanes.indices.contains(pane) else { return }
            self.workspacePanes[pane].selectedNoteID = noteID
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
            if let id = noteID, path != nil {
                recordRecentNote(id)
            }
            if self.workspacePanes[pane].selectedBaseName == path,
                self.workspacePanes[pane].activeDocument?.metadata.noteID == noteID { return }
            if let p = pendingEditorScroll, p.noteID != noteID {
                pendingEditorScroll = nil
            }
            await flushPaneIfDirty(pane)
            self.workspacePanes[pane].navigationGeneration += 1
            self.workspacePanes[pane].selectedBaseName = path
            await loadSelectedNote(pane: pane)
        }
    }

    func refreshOnDiskFingerprints(for path: String, pane: Int) async {
        guard workspacePanes.indices.contains(pane) else { return }
        do {
            workspacePanes[pane].lastKnownDiskDate = try await repository.noteModifiedDate(relativePath: path)
            workspacePanes[pane].lastKnownDiskRevision = try await repository.noteRevisionToken(relativePath: path)
            workspacePanes[pane].lastKnownNoteTextSHA256 = try await repository.noteTextFileSHA256(relativePath: path)
        } catch {
            userAlert = .recoverable(
                message: "Failed to read note on-disk state: \(error.localizedDescription)",
                kind: .retryRefreshOnDiskFingerprints
            )
        }
    }

    /// Cancels any debounced save for the pane, then persists if dirty.
    func flushPaneIfDirty(_ pane: Int) async {
        if let t = saveTasks[pane] {
            t.cancel()
            saveTasks.removeValue(forKey: pane)
        }
        guard workspacePanes.indices.contains(pane) else { return }
        let doc = workspacePanes[pane].activeDocument
        let path = workspacePanes[pane].selectedBaseName
        let last = workspacePanes[pane].lastPersistedDocument
        guard let doc, let path else { return }
        guard doc != last else { return }
        do {
            let integrity = try await repository.save(doc, asBaseName: path)
            applyVaultIntegrityAfterSave(integrity)
            await refreshOnDiskFingerprints(for: path, pane: pane)
            workspacePanes[pane].lastPersistedDocument = doc
            bodySearchIndex[doc.metadata.noteID] = doc.text
            tagIndex[doc.metadata.noteID] = Set(NoteTags.parse(doc.metadata.properties))
            await refreshBacklinks(forPane: pane)
        } catch {
            userAlert = .recoverable(
                message: "Autosave failed: \(error.localizedDescription)",
                kind: .retryFlushActiveNoteToDisk
            )
        }
    }

    private func flushCurrentNoteToDiskIfDirty() async {
        await flushPaneIfDirty(activePaneIndex)
    }

    private func scheduleAutosave(forPane pane: Int) {
        saveTasks[pane]?.cancel()
        saveTasks.removeValue(forKey: pane)
        guard workspacePanes.indices.contains(pane) else { return }
        guard let expectedPath = workspacePanes[pane].selectedBaseName, workspacePanes[pane].activeDocument != nil else {
            return
        }
        let gen = workspacePanes[pane].navigationGeneration
        let startedAt = Date()
        let task = Task { @MainActor in
            defer {
                Task { @MainActor in
                    self.saveTasks.removeValue(forKey: pane)
                    await self.runPendingExternalDiskReconciliationIfNeeded()
                }
            }
            try? await Task.sleep(for: .milliseconds(autosaveDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            guard gen == self.workspacePanes[pane].navigationGeneration else { return }
            guard self.workspacePanes[pane].selectedBaseName == expectedPath else { return }
            guard let latest = self.workspacePanes[pane].activeDocument else { return }
            do {
                let integrity = try await repository.save(latest, asBaseName: expectedPath)
                guard gen == self.workspacePanes[pane].navigationGeneration,
                    self.workspacePanes[pane].selectedBaseName == expectedPath else { return }
                applyVaultIntegrityAfterSave(integrity)
                await refreshOnDiskFingerprints(for: expectedPath, pane: pane)
                self.workspacePanes[pane].lastPersistedDocument = latest
                self.bodySearchIndex[latest.metadata.noteID] = latest.text
                self.tagIndex[latest.metadata.noteID] = Set(NoteTags.parse(latest.metadata.properties))
                let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VaultTelemetry.logAutosave(latencyMs: max(0, latencyMs))
                await self.refreshBacklinks(forPane: pane)
            } catch {
                userAlert = .recoverable(
                    message: "Autosave failed: \(error.localizedDescription)",
                    kind: .retryFlushActiveNoteToDisk
                )
            }
        }
        saveTasks[pane] = task
    }
}
