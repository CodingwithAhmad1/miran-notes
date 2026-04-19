import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultWorkspaceAccessTests: XCTestCase {
    private func tempDir() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranVaultAccess-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(nil)
        super.tearDown()
    }

    func testAdoptPersistsBookmarkAndBootstrapRestoresSameVault() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vault = root.appendingPathComponent("MyVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        let bookmarkFile = root.appendingPathComponent("vault-root.bookmark")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let access1 = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(vault)
        XCTAssertEqual(access1.vaultRootURL.standardizedFileURL.path, vault.standardizedFileURL.path)

        access1.stopAccessingIfNeeded()

        let bogusDefault = root.appendingPathComponent("nonexistent-default", isDirectory: true)
        let outcome2 = VaultWorkspaceAccess.bootstrap(defaultVaultURL: bogusDefault)
        guard case let .resolved(access2) = outcome2 else {
            XCTFail("expected resolved vault from bookmark")
            return
        }
        XCTAssertEqual(access2.vaultRootURL.standardizedFileURL.path, vault.standardizedFileURL.path)

        access2.stopAccessingIfNeeded()
    }

    func testStopAccessingIfNeededIsIdempotent() throws {
        let root = try tempDir()
        let vault = root.appendingPathComponent("V", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        let access = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(vault)
        access.stopAccessingIfNeeded()
        access.stopAccessingIfNeeded()
    }

    func testBootstrapClearsStaleMissingDirectory() throws {
        let root = try tempDir()
        let bookmarkFile = root.appendingPathComponent("bm")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let vault = root.appendingPathComponent("Gone", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(vault)
        try FileManager.default.removeItem(at: vault)

        let defaultVault = root.appendingPathComponent("DefaultVault", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultVault, withIntermediateDirectories: true)

        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: defaultVault)
        guard case let .resolved(access) = outcome else {
            XCTFail("expected resolved fallback vault")
            return
        }
        XCTAssertEqual(access.vaultRootURL.standardizedFileURL.path, defaultVault.standardizedFileURL.path)
        XCTAssertNil(VaultRootBookmarkStore.loadBookmarkData())

        access.stopAccessingIfNeeded()
    }

    func testBootstrapWithNoBookmarkAndNilDefaultNeedsUserSelection() throws {
        let root = try tempDir()
        let bookmarkFile = root.appendingPathComponent("bm")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: nil)
        guard case .needsUserSelectedVault = outcome else {
            XCTFail("expected needsUserSelectedVault when no bookmark and no default URL")
            return
        }
    }

    func testBootstrapIncompatibleBookmarkClearsAndUsesDefaultVault() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vault = root.appendingPathComponent("Marked", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let fallback = root.appendingPathComponent("Fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)

        let bookmarkFile = root.appendingPathComponent("vault-root.bookmark")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let access1 = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(vault)
        access1.stopAccessingIfNeeded()

        let junk = vault.appendingPathComponent("disallowed.pdf")
        try Data().write(to: junk, options: .atomic)

        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: fallback)
        guard case let .resolved(access2) = outcome else {
            XCTFail("expected resolved fallback after incompatible bookmark vault")
            return
        }
        XCTAssertEqual(access2.vaultRootURL.standardizedFileURL.path, fallback.standardizedFileURL.path)
        XCTAssertNil(VaultRootBookmarkStore.loadBookmarkData(), "incompatible bookmark should be cleared; default vault is not auto-bookmarked")
        access2.stopAccessingIfNeeded()
    }

    func testAdoptRejectsIncompatibleVault() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bookmarkFile = root.appendingPathComponent("adopt-reject.bm")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let vault = root.appendingPathComponent("Bad", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let junk = vault.appendingPathComponent("disallowed.pdf")
        try Data().write(to: junk, options: .atomic)

        XCTAssertThrowsError(try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(vault)) { error in
            guard let adoption = error as? VaultWorkspaceAdoptionError else {
                XCTFail("expected VaultWorkspaceAdoptionError")
                return
            }
            guard case .incompatibleVault(let report) = adoption else {
                XCTFail("expected incompatibleVault")
                return
            }
            XCTAssertFalse(report.issues.isEmpty)
            XCTAssertTrue(
                report.issues.contains {
                    $0.code == .disallowedRootFile || $0.code == .disallowedItemInNoteFolder
                }
            )
        }
        XCTAssertNil(VaultRootBookmarkStore.loadBookmarkData())
    }

    func testBootstrapRejectsIncompatibleDefaultVaultURL() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notADir = root.appendingPathComponent("file-not-folder")
        try "x".write(to: notADir, atomically: true, encoding: .utf8)

        let bookmarkFile = root.appendingPathComponent("bm")
        VaultRootBookmarkStore.setBookmarkFileURLForTesting(bookmarkFile)

        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: notADir)
        guard case .needsUserSelectedVault = outcome else {
            XCTFail("expected needsUserSelectedVault when default URL is not a workspace directory")
            return
        }
    }
}
