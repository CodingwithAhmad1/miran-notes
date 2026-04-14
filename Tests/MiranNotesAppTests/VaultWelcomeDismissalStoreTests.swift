import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultWelcomeDismissalStoreTests: XCTestCase {
    func testMarkDismissedCreatesMarker() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()

        XCTAssertFalse(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
        try VaultWelcomeDismissalStore.markDismissed(vaultURL: vault)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
        try VaultWelcomeDismissalStore.markDismissed(vaultURL: vault)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }

    func testLegacyMiranMarkerStillCountsAsDismissed() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let miran = VaultPaths.miranDirectory(vaultURL: vault)
        try FileManager.default.createDirectory(at: miran, withIntermediateDirectories: true)
        let marker = VaultWelcomeDismissalStore.markerURL(vaultURL: vault)
        try Data().write(to: marker, options: .atomic)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }
}
