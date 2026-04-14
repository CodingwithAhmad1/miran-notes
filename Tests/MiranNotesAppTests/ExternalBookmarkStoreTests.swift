import Foundation
import XCTest

@testable import MiranNotesApp

final class ExternalBookmarkStoreTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testUpsertAndStatusTransition() async throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let store = ExternalBookmarkStore(vaultURL: vault)
        let id = UUID()

        try await store.upsert(
            id: id,
            targetDescription: "External Folder",
            bookmarkData: Data([1, 2, 3]),
            status: .valid
        )
        try await store.markStatus(id: id, status: .stale)
        let all = try await store.list()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, id)
        XCTAssertEqual(all[0].status, .stale)
    }
}
