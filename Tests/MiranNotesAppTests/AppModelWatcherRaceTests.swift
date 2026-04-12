import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelWatcherRaceTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesWatcherTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// While autosave is in flight, a watcher event must be deferred — `processExternalDiskActivity`
    /// should not run until after the save task settles. Also verifies that when deferred
    /// reconciliation eventually runs and sees the autosave's own write, it does NOT produce a
    /// spurious conflict alert.
    func testWatcherEventDeferredWhileSaveInFlight() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "race-note")

        let model = AppModel(repository: repo, autosaveDebounceMilliseconds: 100)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        // Make buffer dirty — saveTask is now non-nil for 100 ms.
        model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "local"))

        // Write a competing version to disk before autosave fires.
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "external".write(to: textURL, atomically: true, encoding: .utf8)

        // Watcher fires: saveTask is still in flight, reconciliation must be deferred.
        await model.simulateWatcherEvent()
        XCTAssertNil(
            model.externalEditConflictAlert,
            "Reconciliation should be deferred while autosave is in flight"
        )

        // Wait for autosave (100 ms) + deferred reconciliation to settle.
        // Autosave wins the race: it writes "local" to disk, then deferred reconciliation
        // reads back "local" and finds it matches the buffer — no spurious conflict.
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(
            model.externalEditConflictAlert,
            "Own autosave write must not produce a spurious conflict alert"
        )
    }

    /// Clean buffer + external change → silent automatic reload with no conflict alert.
    func testCleanBufferExternalChangeReloadsAutomatically() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "clean-reload")

        let model = AppModel(repository: repo, autosaveDebounceMilliseconds: 100)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        // Buffer is clean. Ensure a distinct mtime before writing the new version.
        try await Task.sleep(for: .milliseconds(50))
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "new-content".write(to: textURL, atomically: true, encoding: .utf8)

        await model.processExternalDiskActivity()

        XCTAssertNil(model.externalEditConflictAlert, "Clean-buffer external change should reload silently")
        XCTAssertEqual(model.activeDocument?.text, "new-content", "Buffer should reflect the new on-disk content")
    }

    /// Once a conflict alert is showing, subsequent `processExternalDiskActivity` calls are
    /// no-ops — the existing alert is not replaced or duplicated. Coalesces rapid watcher events.
    func testActiveConflictAlertBlocksAdditionalReconciliation() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "coalesce-note")

        let model = AppModel(repository: repo, autosaveDebounceMilliseconds: 100)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        // Dirty buffer + external change → first conflict.
        model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "local"))
        try await Task.sleep(for: .milliseconds(50))
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "external1".write(to: textURL, atomically: true, encoding: .utf8)
        await model.processExternalDiskActivity()

        guard let firstAlert = model.externalEditConflictAlert else {
            XCTFail("Expected a conflict alert from the first external change")
            return
        }

        // Another external change fires while the alert is already displayed.
        try "external2".write(to: textURL, atomically: true, encoding: .utf8)
        await model.processExternalDiskActivity()

        // The existing alert must not be replaced — same stable identity.
        XCTAssertEqual(
            model.externalEditConflictAlert?.id,
            firstAlert.id,
            "Subsequent reconciliation while alert is showing should be a no-op"
        )
    }
}
