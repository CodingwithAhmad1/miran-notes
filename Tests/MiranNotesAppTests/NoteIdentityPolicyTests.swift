import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class NoteIdentityPolicyTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testLoadWithoutMetaUsesManifestNoteID() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Work")
        try await repo.setFolderRole(.repository, folderID: folderID)
        let (doc, path) = try await repo.createNote(named: "alpha", folderID: folderID)
        let expectedID = doc.metadata.noteID

        let metaURL = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: path, extension: "meta.json")
        try FileManager.default.removeItem(at: metaURL)
        await repo.invalidateIndexCaches()

        let manifestURL = VaultPaths.manifestURL(vaultURL: vault)
        let data = try Data(contentsOf: manifestURL)
        var manifest = try JSONDecoder().decode(VaultManifest.self, from: data)
        manifest.ensureSchemaVersionIsCurrent()
        XCTAssertEqual(manifest.entry(relativePath: path)?.noteID, expectedID)

        let loaded = try await repo.loadNote(relativePath: path).document
        XCTAssertEqual(loaded.metadata.noteID, expectedID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path), "Materialization should restore sidecar")
    }

    func testSidecarWinsOverManifestConflict() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, path) = try await repo.createNote(named: "conflict", folderID: FolderCatalog.rootFolderID)
        let metaURL = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: path, extension: "meta.json")
        let sidecarData = try Data(contentsOf: metaURL)
        let meta = try JSONDecoder().decode(NoteMetadata.self, from: sidecarData)
        let trueID = meta.noteID
        let wrongID = UUID()
        XCTAssertNotEqual(trueID, wrongID)

        let manifestURL = VaultPaths.manifestURL(vaultURL: vault)
        let mdata = try Data(contentsOf: manifestURL)
        var manifest = try JSONDecoder().decode(VaultManifest.self, from: mdata)
        if let idx = manifest.entries.firstIndex(where: { $0.relativePath == path }) {
            manifest.entries[idx].noteID = wrongID
        }
        try writeManifestFile(manifest, to: manifestURL)

        let pathIndexURL = VaultPaths.pathIndexURL(vaultURL: vault)
        var pathIndex = try JSONDecoder().decode(PathIndex.self, from: Data(contentsOf: pathIndexURL))
        pathIndex.replaceNoteID(forRelativePath: path, newNoteID: wrongID)
        let piEnc = JSONEncoder()
        piEnc.outputFormatting = [.sortedKeys]
        try piEnc.encode(pathIndex).write(to: pathIndexURL)

        await repo.invalidateIndexCaches()

        let loaded = try await repo.loadNote(relativePath: path).document
        XCTAssertEqual(loaded.metadata.noteID, trueID)

        let repaired = try await repo.loadManifest()
        XCTAssertEqual(repaired.entry(relativePath: path)?.noteID, trueID)

        let piData = try Data(contentsOf: pathIndexURL)
        let pathIndexAfter = try JSONDecoder().decode(PathIndex.self, from: piData)
        XCTAssertEqual(pathIndexAfter.entries.first(where: { $0.relativePath == path })?.noteID, trueID)
    }

    func testRenamePreservesNoteID() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, oldPath) = try await repo.createNote(named: "rename-me", folderID: FolderCatalog.rootFolderID)
        let id = doc.metadata.noteID

        let newPath = try await repo.renameNote(from: oldPath, to: "renamed-title")
        XCTAssertNotEqual(newPath, oldPath)

        let loaded = try await repo.loadNote(relativePath: newPath).document
        XCTAssertEqual(loaded.metadata.noteID, id)
    }

    func testMaterializingSidecarNoOpWhenAlreadyValid() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, path) = try await repo.createNote(named: "stable-meta", folderID: FolderCatalog.rootFolderID)
        let metaURL = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: path, extension: "meta.json")
        let bytesBefore = try Data(contentsOf: metaURL)

        _ = try await repo.loadManifest()

        let bytesAfter = try Data(contentsOf: metaURL)
        XCTAssertEqual(bytesBefore, bytesAfter, "Valid sidecar should not be rewritten during materialization")
    }

    func testMaterializeMissingSidecarContinuesAfterOnePathFails() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "NoWrite")
        try await repo.setFolderRole(.repository, folderID: folderID)
        let (_, lockedPath) = try await repo.createNote(named: "locked-inner", folderID: folderID)
        let (_, openPath) = try await repo.createNote(named: "open-root", folderID: FolderCatalog.rootFolderID)

        let lockedMeta = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: lockedPath, extension: "meta.json")
        let openMeta = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: openPath, extension: "meta.json")
        try FileManager.default.removeItem(at: lockedMeta)
        try FileManager.default.removeItem(at: openMeta)
        await repo.invalidateIndexCaches()

        let folderDir = lockedMeta.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderDir.path)
        }

        _ = try await repo.loadManifest()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: lockedMeta.path),
            "Unwritable folder should block materialization for that note"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: openMeta.path),
            "Materialization should still succeed for other notes"
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderDir.path)
        _ = try await repo.loadManifest()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedMeta.path))
    }

    func testBulkTxtFilesDiscoveredInSingleManifestLoad() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        try FileManager.default.createDirectory(at: vault.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        try "alpha".write(to: vault.appendingPathComponent("import-a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: vault.appendingPathComponent("subdir/import-b.txt"), atomically: true, encoding: .utf8)
        try "gamma".write(to: vault.appendingPathComponent("import-c.txt"), atomically: true, encoding: .utf8)

        let manifest = try await repo.loadManifest()
        let paths = Set(manifest.entries.map(\.relativePath))
        XCTAssertEqual(paths, Set(["import-a", "subdir/import-b", "import-c"]))

        for rel in paths {
            let metaURL = VaultPath.fileURL(vaultRoot: vault, relativePathWithoutExtension: rel, extension: "meta.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
        }
    }

}

private func writeManifestFile(_ manifest: VaultManifest, to url: URL) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(manifest).write(to: url)
}
