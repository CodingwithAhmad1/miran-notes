import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultPathValidationTests: XCTestCase {
    private let vault = URL(fileURLWithPath: "/tmp/miran-vault-test", isDirectory: true)

    func testValidateRelativePathRejectsEmpty() {
        XCTAssertThrowsError(try VaultPath.validateRelativePath("")) { err in
            XCTAssertTrue(err is NoteRepositoryError)
        }
    }

    func testValidateRelativePathRejectsLeadingSlash() {
        XCTAssertThrowsError(try VaultPath.validateRelativePath("/a/b"))
    }

    func testValidateRelativePathRejectsDotDotSegment() {
        XCTAssertThrowsError(try VaultPath.validateRelativePath("a/../b"))
        XCTAssertThrowsError(try VaultPath.validateRelativePath(".."))
    }

    func testValidateRelativePathRejectsDotSegment() {
        XCTAssertThrowsError(try VaultPath.validateRelativePath("a/./b"))
    }

    func testValidateRelativePathRejectsHiddenSegment() {
        XCTAssertThrowsError(try VaultPath.validateRelativePath(".hidden/note"))
    }

    func testValidateRelativePathAcceptsNestedSlugs() throws {
        try VaultPath.validateRelativePath("work/client/meeting-notes")
    }

    func testFileURLBuildsUnderVaultRoot() {
        let url = VaultPath.fileURL(
            vaultRoot: vault,
            relativePathWithoutExtension: "Business/Note",
            extension: "txt"
        )
        XCTAssertTrue(url.path.hasPrefix(vault.path))
        XCTAssertTrue(url.lastPathComponent == "Note.txt")
    }
}
