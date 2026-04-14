import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelUserAlertTests: XCTestCase {
    func testPerformUserAlertRecoveryClearsRecoverableAlert() {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranUserAlert-\(UUID().uuidString)", isDirectory: true)
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)

        model.userAlert = .recoverable(
            message: "Could not update text search for this library.",
            kind: .retryBodySearchIndex
        )
        model.performUserAlertRecovery(kind: .retryBodySearchIndex)

        XCTAssertEqual(model.userAlert, .none)
    }
}
