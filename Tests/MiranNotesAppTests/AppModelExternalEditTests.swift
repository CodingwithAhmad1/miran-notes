import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelExternalEditTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesAppModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testExternalChangeWhileDirtySetsConflictAlert() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "conflict-note")
        let model = AppModel(repository: repo)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "local"))

        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "external".write(to: textURL, atomically: true, encoding: .utf8)

        await model.processExternalDiskActivity()
        XCTAssertNotNil(model.externalEditConflictAlert)
    }

    func testResolveKeepLocalRecordsDiskTimeSoNoImmediateRealert() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "keep-local")
        let model = AppModel(repository: repo)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "L"))

        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "E".write(to: textURL, atomically: true, encoding: .utf8)

        await model.processExternalDiskActivity()
        XCTAssertNotNil(model.externalEditConflictAlert)

        model.resolveExternalEditConflict(reloadFromDisk: false)
        XCTAssertNil(model.externalEditConflictAlert)

        await model.processExternalDiskActivity()
        XCTAssertNil(model.externalEditConflictAlert)
    }

    func testResolveReloadFromDiskReplacesBuffer() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "reload-me")
        let model = AppModel(repository: repo)
        model.selectedBaseName = baseName
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "LOCAL"))

        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "DISK".write(to: textURL, atomically: true, encoding: .utf8)

        await model.processExternalDiskActivity()
        XCTAssertNotNil(model.externalEditConflictAlert)

        model.resolveExternalEditConflict(reloadFromDisk: true)
        XCTAssertNil(model.externalEditConflictAlert)

        for _ in 0..<80 {
            if model.activeDocument?.text == "DISK" { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(model.activeDocument?.text, "DISK")
    }
}
