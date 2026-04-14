import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultWelcomeDismissalStoreTests: XCTestCase {
    func testMarkDismissedCreatesMarker() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranWelcomeDismiss-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: VaultPaths.miranDirectory(vaultURL: vault),
            withIntermediateDirectories: true
        )

        XCTAssertFalse(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
        try VaultWelcomeDismissalStore.markDismissed(vaultURL: vault)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
        try VaultWelcomeDismissalStore.markDismissed(vaultURL: vault)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }
}
