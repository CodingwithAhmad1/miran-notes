// External-edit conflicts, vault watcher pipeline, file presenter (split from AppModel.swift; mechanical move).
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

extension AppModel {
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
        await reconcileVaultState(invalidateCaches: true, refreshNotesOnSuccess: true)
        pendingExternalDiskCheck = true
        await runPendingExternalDiskReconciliationIfNeeded()
    }

    func startVaultWatcher() {
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

    func updateActiveNoteFilePresenter() {
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
}
