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
    /// Which editor surface and modules are active (environment / future Settings).
    var editorActivationProfile: EditorActivationProfile

    var noteSummaries: [NoteSummary] = []
    /// One session per layout tile (size == ``currentLayout/paneCount``).
    var workspacePanes: [WorkspacePaneSession] = [WorkspacePaneSession()]
    /// When set, the editor scrolls to this range once that note is loaded.
    var pendingEditorScroll: PendingEditorScroll?
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
    private(set) var hiddenTopLevelFolderIDs: Set<UUID> = []

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

    private var scopeParentIDForTopLevelFolders: UUID {
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
        return id != FolderCatalog.rootFolderID
    }

    /// Menu / keyboard entry point for new folder; gates on workspace readiness, then delegates to ``createFolder()``.
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

    private var isEligibleForTodaysTasksVaultExperience: Bool {
        workspaceScope == .fullVault && !visibleTopLevelFolderEntries.isEmpty
    }

    /// Full vault with visible top-level folders: the vault tray row is shown as a button.
    var showsVaultTrayAsButton: Bool {
        isEligibleForTodaysTasksVaultExperience
    }

    /// Detail column shows the Today’s Tasks page instead of vault-root notes.
    func showsTodaysTasksVaultRootPage(forPane pane: Int) -> Bool {
        guard isEligibleForTodaysTasksVaultExperience,
            workspacePanes.indices.contains(pane),
            workspacePanes[pane].selectedFolderID == FolderCatalog.rootFolderID
        else { return false }
        return true
    }

    func addTodaysTaskRow() -> UUID {
        let id = UUID()
        todaysTasksItems.append(VaultTodaysTaskRow(id: id, title: "", isDone: false))
        scheduleTodaysTasksPersist()
        return id
    }

    func setTodaysTaskTitle(id: UUID, title: String) {
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == id }) else { return }
        todaysTasksItems[i].title = title
        scheduleTodaysTasksPersist()
    }

    func toggleTodaysTaskDone(id: UUID) {
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == id }) else { return }
        todaysTasksItems[i].isDone.toggle()
        scheduleTodaysTasksPersist()
    }

    func bindingForTodaysTaskTitle(id: UUID) -> Binding<String> {
        Binding(
            get: { self.todaysTasksItems.first { $0.id == id }?.title ?? "" },
            set: { self.setTodaysTaskTitle(id: id, title: $0) }
        )
    }

    var todaysTasksSelectedDayDisplayShort: String {
        todaysTasksSelectedDay.displayShortYYMMDD(calendar: Self.vaultTasksCalendar())
    }

    var canGoToPreviousTodaysTasksDay: Bool {
        VaultTasksDayNavigation.previous(before: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) != nil
    }

    var canGoToNextTodaysTasksDay: Bool {
        VaultTasksDayNavigation.next(after: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) != nil
    }

    func goToPreviousTodaysTasksDay() {
        guard let prev = VaultTasksDayNavigation.previous(before: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        todaysTasksSelectedDay = prev
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: prev, vaultURL: repository.vaultURL)
    }

    func goToNextTodaysTasksDay() {
        guard let next = VaultTasksDayNavigation.next(after: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        todaysTasksSelectedDay = next
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: next, vaultURL: repository.vaultURL)
    }

    /// Call when the app may have crossed midnight (e.g. scene became active). Snaps selection to wall-clock today and ensures that page exists.
    func refreshTodaysTasksIfCalendarDayChanged() {
        let cal = Self.vaultTasksCalendar()
        let today = VaultTasksCalendarDay.today(calendar: cal)
        guard today != todaysTasksSelectedDay else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        do {
            var known = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: repository.vaultURL, calendar: cal)
            if !known.contains(today) {
                try VaultTodaysTasksDayStore.save(day: today, items: [], vaultURL: repository.vaultURL)
                known = try VaultTodaysTasksIndexStore.insertDayIfMissing(today, vaultURL: repository.vaultURL, existing: known)
            }
            todaysTasksKnownDays = known
            todaysTasksSelectedDay = today
            todaysTasksItems = VaultTodaysTasksDayStore.load(day: today, vaultURL: repository.vaultURL)
        } catch {
            userAlert = .message("Could not update Today’s Tasks for the new day: \(error.localizedDescription)")
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
    private let bodySearchIndexController = NoteBodySearchIndexController()
    private let backlinkRefreshScheduler = DebouncedAsyncWorkScheduler()
    /// In-flight debounced autosave tasks keyed by pane index.
    private var saveTasks: [Int: Task<Void, Never>] = [:]
    private var todaysTasksPersistTask: Task<Void, Never>?
    private var vaultWatcherSubscription: VaultWatcherSubscription?
    /// Set when the vault watcher fires; processed after autosave finishes so events are not dropped.
    private var pendingExternalDiskCheck = false
    private var undoManager: UndoManager?
    private let undoPolicy: UndoPolicy
    /// Pane index used by window-level bindings (toolbar, menu); always in range of ``workspacePanes``.
    private var keyPaneIndex: Int {
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

    private let autosaveDebounceMilliseconds: UInt64
    private let largeVaultLinkGraphSyncThreshold: Int
    private let startupLinkGraphSyncBudgetMs: Double
    private let startupLinkGraphSyncHistoryWeight: Double
    private var startupLinkGraphSyncTask: Task<Void, Never>?
    private var activeNoteFilePresenter: ActiveNoteFilePresenter?

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

    private static func vaultTasksCalendar() -> Calendar {
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

    func refreshNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            noteSummaries = try await repository.listNotes().sorted(by: Self.noteSummarySortPredicate)
            folderCatalog = try await repository.loadFolderCatalog()
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

    private func reconcileHiddenFoldersWithCatalogIfNeeded() {
        let parent = scopeParentIDForTopLevelFolders
        let pruned = VaultHiddenFoldersStore.pruned(
            hiddenTopLevelFolderIDs,
            folderCatalog: folderCatalog,
            parentFolderID: parent
        )
        guard pruned != hiddenTopLevelFolderIDs else { return }
        hiddenTopLevelFolderIDs = pruned
        VaultHiddenFoldersStore.save(pruned, vaultURL: repository.vaultURL)
    }

    private func persistHiddenTopLevelFolderIDs() {
        VaultHiddenFoldersStore.save(hiddenTopLevelFolderIDs, vaultURL: repository.vaultURL)
    }

    func hideTopLevelFolders(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        hiddenTopLevelFolderIDs.formUnion(ids)
        persistHiddenTopLevelFolderIDs()
        for i in workspacePanes.indices {
            if let selected = workspacePanes[i].selectedFolderID, ids.contains(selected) {
                workspacePanes[i].selectedFolderID = pickDefaultFolderID()
            }
        }
    }

    func unhideTopLevelFolders(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        hiddenTopLevelFolderIDs.subtract(ids)
        persistHiddenTopLevelFolderIDs()
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

    private func pickDefaultFolderID() -> UUID? {
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

    private func applyIncompatibleWorkspaceReport(_ report: CompatibilityReport) {
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

    /// Hierarchical rows for the sidebar (`FolderCatalog` + notes from `filteredNoteSummaries`).
    var sidebarOutline: [SidebarOutlineEntry] {
        sidebarOutline(forPane: activePaneIndex)
    }

    func sidebarOutline(forPane pane: Int) -> [SidebarOutlineEntry] {
        Self.buildSidebarOutline(
            folderCatalog: folderCatalog,
            notes: filteredNoteSummaries(forPane: pane),
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
        let noteList = notes.filter { $0.folderID == parentID }
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

    func createFolder(parentID: UUID = FolderCatalog.rootFolderID, name: String = "New Folder", pane: Int? = nil) {
        let targetPane = pane ?? activePaneIndex
        Task { @MainActor in
            do {
                let id = try await repository.createFolder(parentID: parentID, name: name)
                markVaultWelcomeDismissedIfNeeded()
                await refreshNotes()
                self.workspacePanes[targetPane].selectedFolderID = id
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
                hiddenTopLevelFolderIDs.remove(id)
                persistHiddenTopLevelFolderIDs()
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Deletes several folders in order; refreshes once after all succeed. On first failure, refreshes and sets ``userAlert``.
    func deleteTopLevelFolders(ids: Set<UUID>, onSuccess: @escaping @MainActor (_ deletedCount: Int) -> Void) {
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            var deleted = 0
            for id in ids {
                do {
                    try await repository.deleteFolder(id: id)
                    hiddenTopLevelFolderIDs.remove(id)
                    deleted += 1
                } catch {
                    persistHiddenTopLevelFolderIDs()
                    await refreshNotes()
                    userAlert = .recoverable(
                        message: error.localizedDescription,
                        kind: .retryRefreshNotesAndFolderUI
                    )
                    return
                }
            }
            persistHiddenTopLevelFolderIDs()
            await refreshNotes()
            onSuccess(deleted)
        }
    }

    func deleteSelectedNote(pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard let path = workspacePanes[pane].selectedBaseName else { return }
        Task { @MainActor in
            do {
                let manifest = try await repository.loadManifest()
                guard let id = manifest.entry(relativePath: path)?.noteID else { return }
                try await repository.deleteNote(noteID: id)
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
    var filteredNoteSummaries: [NoteSummary] {
        filteredNoteSummaries(forPane: activePaneIndex)
    }

    func filteredNoteSummaries(forPane pane: Int) -> [NoteSummary] {
        let q = workspacePanes[pane].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return noteSummaries }
        return noteSummaries.filter { vaultNameOrPathMatches($0, queryLowercased: q) }
    }

    /// Vault-wide note rows matching the pane's vault search (sorted by title).
    var vaultSearchMatchingNoteSummaries: [NoteSummary] {
        vaultSearchMatchingNoteSummaries(forPane: activePaneIndex)
    }

    func vaultSearchMatchingNoteSummaries(forPane pane: Int) -> [NoteSummary] {
        let q = workspacePanes[pane].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return noteSummaries
            .filter { vaultNameOrPathMatches($0, queryLowercased: q) }
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
        await refreshBacklinks(forPane: activePaneIndex)
    }

    func refreshBacklinks(forPane pane: Int) async {
        guard workspacePanes.indices.contains(pane) else { return }
        guard let doc = workspacePanes[pane].activeDocument else {
            workspacePanes[pane].backlinks = []
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
            workspacePanes[pane].backlinks = result
        } catch {
            workspacePanes[pane].backlinks = []
            userAlert = .recoverable(
                message: "Could not refresh backlinks: \(error.localizedDescription)",
                kind: .retryRefreshBacklinks
            )
        }
    }

    private func scheduleBacklinkRefresh(forPane pane: Int) {
        backlinkRefreshScheduler.schedule(delay: .milliseconds(1500)) { [weak self] in
            guard let self else { return }
            await self.refreshBacklinks(forPane: pane)
        }
    }

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

    func openBacklinkSource(_ item: BacklinkItem, pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        if !item.linkRange.isEmpty {
            pendingEditorScroll = PendingEditorScroll(noteID: item.sourceNoteID, range: item.linkRange)
        } else {
            pendingEditorScroll = nil
        }
        if workspacePanes[p].activeDocument?.metadata.noteID == item.sourceNoteID {
            return
        }
        changeSelection(noteID: item.sourceNoteID, pane: p)
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

    private func resolvedBodyExtensionForNewNote(in folderID: UUID) -> String? {
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

    private func resolvedBodyFileExtensionForSelectedNote(pane: Int) -> String {
        guard workspacePanes.indices.contains(pane),
              let noteID = workspacePanes[pane].selectedNoteID,
              let summary = noteSummaries.first(where: { $0.noteID == noteID })
        else {
            return "txt"
        }
        return summary.bodyFileExtension
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

    private func reregisterAllUndoActions(forPane pane: Int) {
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

    private func clearUndoStack(forPane pane: Int) {
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

    private func refreshOnDiskFingerprints(for path: String, pane: Int) async {
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
    private func flushPaneIfDirty(_ pane: Int) async {
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

    private func scheduleTodaysTasksPersist() {
        todaysTasksPersistTask?.cancel()
        todaysTasksPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(autosaveDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            let day = self.todaysTasksSelectedDay
            let items = self.todaysTasksItems
            do {
                try VaultTodaysTasksDayStore.save(day: day, items: items, vaultURL: self.repository.vaultURL)
            } catch {
                userAlert = .message("Could not save Today’s Tasks: \(error.localizedDescription)")
            }
        }
    }

    private func loadVaultTodaysTasksStateAfterPreferences() throws {
        let cal = Self.vaultTasksCalendar()
        let vaultURL = repository.vaultURL
        var known = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: vaultURL, calendar: cal)
        let today = VaultTasksCalendarDay.today(calendar: cal)
        if !known.contains(today) {
            try VaultTodaysTasksDayStore.save(day: today, items: [], vaultURL: vaultURL)
            known = try VaultTodaysTasksIndexStore.insertDayIfMissing(today, vaultURL: vaultURL, existing: known)
        }
        todaysTasksKnownDays = known
        todaysTasksSelectedDay = today
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: today, vaultURL: vaultURL)
    }

    private func persistTodaysTasksImmediatelyForSelectedDay() {
        todaysTasksPersistTask?.cancel()
        todaysTasksPersistTask = nil
        do {
            try VaultTodaysTasksDayStore.save(
                day: todaysTasksSelectedDay,
                items: todaysTasksItems,
                vaultURL: repository.vaultURL
            )
        } catch {
            userAlert = .message("Could not save Today’s Tasks: \(error.localizedDescription)")
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
        let pane = activePaneIndex
        if reloadFromDisk {
            Task { @MainActor in
                await loadSelectedNote(pane: pane)
            }
        } else if let path = workspacePanes[pane].selectedBaseName {
            Task { @MainActor in
                await refreshOnDiskFingerprints(for: path, pane: pane)
            }
        } else if let diskDate {
            workspacePanes[pane].lastKnownDiskDate = diskDate
            workspacePanes[pane].lastKnownDiskRevision = diskRevision
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
        guard saveTasks.isEmpty else { return }
        pendingExternalDiskCheck = false
        await processExternalDiskActivity()
    }

    /// Package-internal for tests that simulate vault changes without relying on filesystem timing.
    func processExternalDiskActivity() async {
        guard externalEditConflictAlert == nil else { return }
        let pane = activePaneIndex
        guard workspacePanes.indices.contains(pane) else { return }
        guard let path = workspacePanes[pane].selectedBaseName, workspacePanes[pane].activeDocument != nil else { return }

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
        if let diskRevision, diskRevision == workspacePanes[pane].lastKnownDiskRevision {
            workspacePanes[pane].lastKnownDiskDate = diskDate
            if let h = try? await repository.noteTextFileSHA256(relativePath: path) {
                workspacePanes[pane].lastKnownNoteTextSHA256 = h
            }
            return
        }
        if let lastKnown = workspacePanes[pane].lastKnownDiskDate, diskDate <= lastKnown {
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

        let isDirty = workspacePanes[pane].lastPersistedDocument != workspacePanes[pane].activeDocument

        if !isDirty {
            if loadedFromDisk == workspacePanes[pane].activeDocument {
                workspacePanes[pane].lastKnownDiskDate = diskDate
                workspacePanes[pane].lastKnownDiskRevision = diskRevision
                workspacePanes[pane].lastKnownNoteTextSHA256 = observedTextHash
                return
            }
            clearUndoStack(forPane: pane)
            workspacePanes[pane].activeDocument = loadedFromDisk
            workspacePanes[pane].lastPersistedDocument = loadedFromDisk
            workspacePanes[pane].lastKnownDiskDate = diskDate
            workspacePanes[pane].lastKnownDiskRevision = diskRevision
            workspacePanes[pane].lastKnownNoteTextSHA256 = observedTextHash
            Task { @MainActor in await refreshBacklinks(forPane: pane) }
            return
        }

        if loadedFromDisk == workspacePanes[pane].activeDocument {
            workspacePanes[pane].lastPersistedDocument = loadedFromDisk
            workspacePanes[pane].lastKnownDiskDate = diskDate
            workspacePanes[pane].lastKnownDiskRevision = diskRevision
            workspacePanes[pane].lastKnownNoteTextSHA256 = observedTextHash
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
        let pane = activePaneIndex
        guard workspacePanes.indices.contains(pane),
            let path = workspacePanes[pane].selectedBaseName else { return }
        let ext = resolvedBodyFileExtensionForSelectedNote(pane: pane)
        let url = VaultPath.fileURL(vaultRoot: repository.vaultURL, relativePathWithoutExtension: path, extension: ext)
        let presenter = ActiveNoteFilePresenter(fileURL: url) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleActiveNotePresenterDidChange(noteRelativePath: path, pane: pane)
            }
        }
        presenter.start()
        activeNoteFilePresenter = presenter
    }

    /// `NSFilePresenter` only observes the active note body file (`.txt` or `.md`). If its body bytes still match the pane's last known hash, skip queuing a full reconciliation.
    private func handleActiveNotePresenterDidChange(noteRelativePath path: String, pane: Int) async {
        guard workspacePanes.indices.contains(pane) else { return }
        do {
            let h = try await repository.noteTextFileSHA256(relativePath: path)
            if let known = workspacePanes[pane].lastKnownNoteTextSHA256, h == known {
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

    /// Switches to a new pane layout. Flushes the active pane, then grows or shrinks ``workspacePanes``.
    func setLayout(_ layout: PaneLayout) {
        Task { @MainActor in
            let newCount = layout.paneCount
            let flushIndex = keyPaneIndex
            await flushPaneIfDirty(flushIndex)
            activePaneIndex = min(max(0, activePaneIndex), max(0, newCount - 1))
            if workspacePanes.count < newCount {
                while workspacePanes.count < newCount {
                    workspacePanes.append(WorkspacePaneSession())
                }
            } else if workspacePanes.count > newCount {
                workspacePanes = Array(workspacePanes.prefix(newCount))
            }
            currentLayout = layout
            undoManager?.removeAllActions(withTarget: self)
            reregisterAllUndoActions(forPane: activePaneIndex)
            updateActiveNoteFilePresenter()
        }
    }

    /// Makes `index` the pane that receives toolbar/search/primary undo registration. Each tile keeps its own navigation state.
    func activatePane(index: Int) {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        Task { await activatePaneAwaitable(index: index) }
    }

    /// Switches the key pane immediately so a synchronous ``apply`` runs against the correct buffer; previous pane flush runs in the background.
    func activatePaneForEditingSync(_ index: Int) {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        let previous = activePaneIndex
        Task { await flushPaneIfDirty(previous) }
        undoManager?.removeAllActions(withTarget: self)
        activePaneIndex = index
        reregisterAllUndoActions(forPane: index)
        updateActiveNoteFilePresenter()
    }

    /// Awaitable activation (e.g. before applying edits so ``apply`` targets the key pane).
    func activatePaneAwaitable(index: Int) async {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        let previous = activePaneIndex
        await flushPaneIfDirty(previous)
        undoManager?.removeAllActions(withTarget: self)
        activePaneIndex = index
        reregisterAllUndoActions(forPane: index)
        updateActiveNoteFilePresenter()
    }
}
