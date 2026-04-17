import Foundation
import XCTest

@testable import MiranNotesApp

final class WorkspaceCompatibilityScannerTests: XCTestCase {
    private func tempRoot() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranWorkspaceScan-\(UUID().uuidString)", isDirectory: true)
    }

    func testEmptyWorkspace() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".miran", isDirectory: true), withIntermediateDirectories: true)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .empty = outcome else {
            return XCTFail("Expected .empty, got \(outcome)")
        }
    }

    func testCompatibleTopicFolderWithTxt() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Business", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        try "hello".write(to: topic.appendingPathComponent("Note.txt"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .compatible(let scan) = outcome else {
            return XCTFail("Expected .compatible, got \(outcome)")
        }
        XCTAssertEqual(scan.folders.count, 1)
        XCTAssertEqual(scan.notes.count, 1)
        XCTAssertEqual(scan.notes[0].relativePathWithoutExtension, "Business/Note")
    }

    func testRootTxtAllowed() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "root".write(to: root.appendingPathComponent("RootNote.txt"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .compatible(let scan) = outcome else {
            return XCTFail("Expected .compatible, got \(outcome)")
        }
        XCTAssertTrue(scan.folders.isEmpty)
        XCTAssertEqual(scan.notes.count, 1)
        XCTAssertEqual(scan.notes[0].relativePathWithoutExtension, "RootNote")
        XCTAssertNil(scan.notes[0].parentFolderName)
    }

    func testNestedFolderRejected() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Business", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        let nested = topic.appendingPathComponent("Inside", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .incompatible(let report) = outcome else {
            return XCTFail("Expected .incompatible, got \(outcome)")
        }
        XCTAssertTrue(report.issues.contains { $0.code == .nestedFolder })
    }

    func testNonNoteBodyFileInTopicFolderRejected() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Business", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        try "x".write(to: topic.appendingPathComponent("notes.doc"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .incompatible(let report) = outcome else {
            return XCTFail("Expected .incompatible, got \(outcome)")
        }
        XCTAssertTrue(report.issues.contains { $0.code == .disallowedItemInNoteFolder })
    }

    func testCompatibleTopicFolderWithMdOnly() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        try "# Hello".write(to: topic.appendingPathComponent("Readme.md"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .compatible(let scan) = outcome else {
            return XCTFail("Expected .compatible, got \(outcome)")
        }
        XCTAssertEqual(scan.notes.count, 1)
        XCTAssertEqual(scan.notes[0].relativePathWithoutExtension, "Docs/Readme")
    }

    func testMixedTxtAndMdInTopicFolderRejected() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Mixed", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        try "a".write(to: topic.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: topic.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .incompatible(let report) = outcome else {
            return XCTFail("Expected .incompatible, got \(outcome)")
        }
        XCTAssertTrue(report.issues.contains { $0.code == .mixedNoteBodyExtensionsInFolder })
    }

    func testRootMixedTxtAndMdRejected() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .incompatible(let report) = outcome else {
            return XCTFail("Expected .incompatible, got \(outcome)")
        }
        XCTAssertTrue(report.issues.contains { $0.code == .mixedNoteBodyExtensionsInFolder })
    }

    func testMetaJsonSidecarIgnored() throws {
        let root = try tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Business", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        try "{}".write(to: topic.appendingPathComponent("Note.meta.json"), atomically: true, encoding: .utf8)
        try "t".write(to: topic.appendingPathComponent("Note.txt"), atomically: true, encoding: .utf8)

        let outcome = WorkspaceCompatibilityScanner.scan(vaultRoot: root)
        guard case .compatible(let scan) = outcome else {
            return XCTFail("Expected .compatible, got \(outcome)")
        }
        XCTAssertEqual(scan.notes.count, 1)
    }
}
