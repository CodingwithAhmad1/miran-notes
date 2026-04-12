import Foundation
import MiranNotesCore
import os.log

/// A single vault write operation expressed as two phases:
/// 1. `prepare` — write data to a temp URL without touching vault files. Returns `(tempURL, finalURL)`.
/// 2. Commit — coordinator renames each temp file to its final location.
struct VaultCommitOperation {
    let participantID: String
    let operationID: String
    /// Phase 1: write to a temp path. Must not modify any vault file directly.
    /// Returns `(tempURL, finalURL)`. If `nil`, the operation is a no-op (skipped).
    let prepare: () throws -> (URL, URL)?
}

struct VaultCommitPlan {
    let label: String
    let operations: [VaultCommitOperation]
    /// Files or empty directories to remove after all commit renames succeed (e.g. old note path after rename).
    let deletePathsAfterCommit: [URL]

    init(label: String, operations: [VaultCommitOperation], deletePathsAfterCommit: [URL] = []) {
        self.label = label
        self.operations = operations
        self.deletePathsAfterCommit = deletePathsAfterCommit
    }
}

protocol VaultCommitParticipant {
    var participantID: String { get }
    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation]
}

struct VaultCommitContext {
    /// Canonical note path without extension (for logging); use `"indexes"` for index-only commits.
    let relativePath: String
    /// When false, note `.txt` / `.meta.json` operations are skipped (index-only commit).
    let includeNoteFiles: Bool
    /// Present only when ``includeNoteFiles`` is true.
    let document: NoteDocument?
    let textURL: URL?
    let metaURL: URL?
    let manifestURL: URL
    let linkGraphURL: URL
    let relationshipIndexURL: URL
    let folderCatalogURL: URL
    let pathIndexURL: URL
    let encoder: JSONEncoder
    let manifest: VaultManifest
    let linkGraph: LinkGraph
    let relationshipIndex: RelationshipIndex
    let folderCatalog: FolderCatalog
    let pathIndex: PathIndex
    let tempDirectory: URL
}

// MARK: - On-disk journal (crash recovery)

private struct VaultCommitJournal: Codable, Equatable {
    static let journalSchemaVersion = 1

    var journalSchemaVersion: Int
    var label: String
    /// Standardized path; must match the vault root when recovering.
    var vaultRootPath: String
    var phase: Phase
    /// Number of rename operations successfully applied to final paths.
    var completedRenameCount: Int
    var operations: [JournalOperation]
    var deletePathsAfterCommit: [String]

    enum Phase: String, Codable {
        /// All temp files written; renames not started.
        case prepared
        /// At least one rename attempted or completed.
        case committing
    }

    struct JournalOperation: Codable, Equatable {
        /// Basename within the staging directory (e.g. `note.txt`).
        var tempFileName: String
        /// Absolute file path (standardized).
        var finalPath: String
    }
}

struct VaultRecoverySummary: Equatable, Sendable {
    /// Staging directories that finished renames + cleanup successfully.
    var resumedAndCompletedCount: Int
    /// Staging directories removed after incomplete prepare or corrupt journal.
    var discardedStagingCount: Int
}

enum VaultCommitSimulationError: Error {
    /// Simulated crash for tests (`testFailAfterRenameCount`).
    case simulatedFailureAfterRenames
}

/// Two-phase atomic commit coordinator with vault-local staging and a persisted journal for resume.
///
/// Phase 1 (prepare): all participants write payloads under `stagingDirectory` (under `vault/.miran/pending-commits/`).
/// Phase 2 (commit): each temp file is renamed into the vault; the journal is updated after each rename.
///
/// If Phase 1 fails, the staging directory is removed and no vault file is touched.
/// If Phase 2 fails after the journal exists, the staging directory is **left in place** for `recoverPendingCommits`.
struct VaultCommitCoordinator {
    /// When set, throws after this many successful renames (tests only).
    var testFailAfterRenameCount: Int?

    private let journalFileName = "vault-commit.json"

    func execute(
        _ plan: VaultCommitPlan,
        vaultRoot: URL,
        stagingDirectory: URL
    ) throws {
        guard !plan.operations.isEmpty else { return }
        let vaultRootStandard = vaultRoot.standardizedFileURL
        Logger.vault.debug("VaultCommit begin label=\(plan.label, privacy: .public) ops=\(plan.operations.count, privacy: .public)")

        var pending: [(tempURL: URL, finalURL: URL, participantID: String, operationID: String)] = []
        do {
            for operation in plan.operations {
                if let pair = try operation.prepare() {
                    pending.append((pair.0, pair.1, operation.participantID, operation.operationID))
                }
            }
        } catch {
            for item in pending {
                try? FileManager.default.removeItem(at: item.tempURL)
            }
            try? FileManager.default.removeItem(at: stagingDirectory)
            Logger.vault.error("VaultCommit Phase 1 failed for \(plan.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard !pending.isEmpty else {
            Logger.vault.debug("VaultCommit nothing to commit label=\(plan.label, privacy: .public)")
            try? FileManager.default.removeItem(at: stagingDirectory)
            return
        }

        let journalOps: [VaultCommitJournal.JournalOperation] = try pending.map { item in
            let name = item.tempURL.lastPathComponent
            guard !name.isEmpty else {
                throw NSError(domain: "VaultCommit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty temp file name"])
            }
            return VaultCommitJournal.JournalOperation(
                tempFileName: name,
                finalPath: item.finalURL.standardizedFileURL.path
            )
        }

        let deleteStrings = plan.deletePathsAfterCommit.map(\.standardizedFileURL.path)

        var journal = VaultCommitJournal(
            journalSchemaVersion: VaultCommitJournal.journalSchemaVersion,
            label: plan.label,
            vaultRootPath: vaultRootStandard.path,
            phase: .prepared,
            completedRenameCount: 0,
            operations: journalOps,
            deletePathsAfterCommit: deleteStrings
        )

        try writeJournal(journal, stagingDirectory: stagingDirectory)
        journal.phase = .committing
        try writeJournal(journal, stagingDirectory: stagingDirectory)

        do {
            try renameLoop(
                pending: pending,
                stagingDirectory: stagingDirectory,
                journal: &journal
            )

            for url in plan.deletePathsAfterCommit {
                do {
                    try FileManager.default.removeItem(at: url)
                    Logger.vault.debug("VaultCommit deleted \(url.path, privacy: .public)")
                } catch {
                    Logger.vault.error("VaultCommit post-delete failed \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            try FileManager.default.removeItem(at: stagingDirectory)
            Logger.vault.debug("VaultCommit complete label=\(plan.label, privacy: .public)")
        } catch {
            // Journal exists: leave staging in place for `recoverPendingCommits`.
            Logger.vault.error("VaultCommit Phase 2 failed for \(plan.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func renameLoop(
        pending: [(tempURL: URL, finalURL: URL, participantID: String, operationID: String)],
        stagingDirectory: URL,
        journal: inout VaultCommitJournal
    ) throws {
        var renamesDone = 0
        for item in pending {
            try applyOneRename(
                tempURL: item.tempURL,
                finalURL: item.finalURL,
                participantID: item.participantID,
                operationID: item.operationID
            )
            renamesDone += 1
            journal.completedRenameCount = renamesDone
            try writeJournal(journal, stagingDirectory: stagingDirectory)

            if let limit = testFailAfterRenameCount, renamesDone == limit {
                throw VaultCommitSimulationError.simulatedFailureAfterRenames
            }
        }
    }

    private func applyOneRename(
        tempURL: URL,
        finalURL: URL,
        participantID: String,
        operationID: String
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: tempURL.path) {
            if fm.fileExists(atPath: finalURL.path) {
                _ = try fm.replaceItemAt(finalURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: finalURL)
            }
        } else if fm.fileExists(atPath: finalURL.path) {
            // Resume path: rename already applied earlier.
        } else {
            throw NSError(
                domain: "VaultCommit",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing temp and final for \(finalURL.path)"]
            )
        }
        Logger.vault.debug(
            "VaultCommit op participant=\(participantID, privacy: .public) op=\(operationID, privacy: .public)"
        )
    }

    private func writeJournal(_ journal: VaultCommitJournal, stagingDirectory: URL) throws {
        let url = stagingDirectory.appendingPathComponent(journalFileName)
        let tmp = stagingDirectory.appendingPathComponent("\(journalFileName).tmp")
        let data = try JSONEncoder().encode(journal)
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Resume or discard pending staging directories left after a crash. Call before normal vault operations.
    static func recoverPendingCommits(vaultRoot: URL) throws -> VaultRecoverySummary {
        let fm = FileManager.default
        let root = VaultPaths.pendingCommitsDirectory(vaultURL: vaultRoot)
        guard fm.fileExists(atPath: root.path) else {
            return VaultRecoverySummary(resumedAndCompletedCount: 0, discardedStagingCount: 0)
        }
        let vaultStandard = vaultRoot.standardizedFileURL
        var resumed = 0
        var discarded = 0

        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for dir in children {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            do {
                if try resumeOrDiscardStaging(stagingDirectory: dir, vaultRoot: vaultStandard) {
                    resumed += 1
                } else {
                    discarded += 1
                }
            } catch {
                Logger.vault.error("Vault recovery failed for \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? fm.removeItem(at: dir)
                discarded += 1
            }
        }
        return VaultRecoverySummary(resumedAndCompletedCount: resumed, discardedStagingCount: discarded)
    }

    /// Returns `true` if a commit was completed from journal; `false` if the staging dir was discarded.
    private static func resumeOrDiscardStaging(stagingDirectory: URL, vaultRoot: URL) throws -> Bool {
        let fm = FileManager.default
        let journalURL = stagingDirectory.appendingPathComponent("vault-commit.json")
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(VaultCommitJournal.self, from: data) else {
            try fm.removeItem(at: stagingDirectory)
            return false
        }

        guard journal.vaultRootPath == vaultRoot.path else {
            Logger.vault.error("Vault recovery: vault root mismatch; discarding staging \(stagingDirectory.path, privacy: .public)")
            try fm.removeItem(at: stagingDirectory)
            return false
        }

        guard journal.journalSchemaVersion == VaultCommitJournal.journalSchemaVersion else {
            try fm.removeItem(at: stagingDirectory)
            return false
        }

        // Apply any pending renames. Ignore `completedRenameCount` if it is stale (crash before journal update).
        for op in journal.operations {
            let tempURL = stagingDirectory.appendingPathComponent(op.tempFileName)
            let finalURL = URL(fileURLWithPath: op.finalPath)
            if fm.fileExists(atPath: tempURL.path) {
                if fm.fileExists(atPath: finalURL.path) {
                    _ = try fm.replaceItemAt(finalURL, withItemAt: tempURL)
                } else {
                    try fm.moveItem(at: tempURL, to: finalURL)
                }
            } else if fm.fileExists(atPath: finalURL.path) {
                continue
            } else {
                try fm.removeItem(at: stagingDirectory)
                return false
            }
        }

        for path in journal.deletePathsAfterCommit {
            let u = URL(fileURLWithPath: path)
            try? fm.removeItem(at: u)
        }

        try fm.removeItem(at: stagingDirectory)
        return true
    }
}
