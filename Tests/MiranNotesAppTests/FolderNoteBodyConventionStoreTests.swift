import Foundation
import XCTest

@testable import MiranNotesApp

final class FolderNoteBodyConventionStoreTests: XCTestCase {
    func testRoundTripPersistsNormalizedExtensions() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let id = UUID()
        var map: [UUID: String] = [id: "MD"]
        try FolderNoteBodyConventionStore.save(map, vaultURL: vault)
        let loaded = FolderNoteBodyConventionStore.load(vaultURL: vault)
        XCTAssertEqual(loaded[id], "md")
    }
}
