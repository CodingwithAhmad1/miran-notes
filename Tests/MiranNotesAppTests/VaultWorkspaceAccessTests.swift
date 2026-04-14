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
        let access2 = VaultWorkspaceAccess.bootstrap(defaultVaultURL: bogusDefault)
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

        let access = VaultWorkspaceAccess.bootstrap(defaultVaultURL: defaultVault)
        XCTAssertEqual(access.vaultRootURL.standardizedFileURL.path, defaultVault.standardizedFileURL.path)
        XCTAssertNil(VaultRootBookmarkStore.loadBookmarkData())

        access.stopAccessingIfNeeded()
    }
}
