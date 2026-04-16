import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelUserAlertTests: XCTestCase {
    func testPerformUserAlertRecoveryClearsRecoverableAlert() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)

        model.userAlert = .recoverable(
            message: "Could not update text search for this library.",
            kind: .retryBodySearchIndex
        )
        model.performUserAlertRecovery(kind: .retryBodySearchIndex)

        XCTAssertEqual(model.userAlert, .none)
    }

    func testPerformUserAlertRecoveryClearsForVariousKinds() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)
        let noteID = UUID()

        let kinds: [UserAlertRecoveryKind] = [
            .retryBodySearchIndex,
            .retryVaultStartupRecovery,
            .retryStartupLinkGraphSync,
            .retryManifestReconcileAfterDiskChange(invalidateCaches: false),
            .retryManifestReconcileAfterDiskChange(invalidateCaches: true),
            .retryRefreshNotesAndFolderUI,
            .retryRefreshBacklinks,
            .retryLoadActiveNote,
            .retryResolveNoteSelection(noteID: noteID),
            .retryRefreshOnDiskFingerprints,
            .retryFlushActiveNoteToDisk,
            .retryVaultWatcher,
            .retryProcessExternalDiskActivity,
            .retryOpenExternalEditCompare,
            .retryLoadNoteInPane(pane: 1, baseName: "test-note"),
        ]

        for kind in kinds {
            model.userAlert = .recoverable(message: "test", kind: kind)
            model.performUserAlertRecovery(kind: kind)
            XCTAssertEqual(model.userAlert, .none, "Expected alert cleared for \(kind)")
        }
    }
}
