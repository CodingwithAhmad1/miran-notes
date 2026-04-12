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
}

protocol VaultCommitParticipant {
    var participantID: String { get }
    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation]
}

struct VaultCommitContext {
    let baseName: String
    let document: NoteDocument
    let textURL: URL
    let metaURL: URL
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
    let atomicWrite: (Data, URL) throws -> Void
    let tempDirectory: URL
}

/// Two-phase atomic commit coordinator.
///
/// Phase 1 (prepare): all participants write their payloads to temp files.
/// Phase 2 (commit): each temp file is renamed to its final vault location using
/// `FileManager.replaceItemAt` / `moveItem(at:to:)` — each rename is individually atomic.
///
/// If Phase 1 fails, all temp files are cleaned up and no vault file is touched.
/// If Phase 2 fails mid-way, already-committed files are left in place and the failure is logged.
struct VaultCommitCoordinator {
    func execute(_ plan: VaultCommitPlan) throws {
        guard !plan.operations.isEmpty else { return }
        Logger.vault.debug("VaultCommit begin label=\(plan.label, privacy: .public) ops=\(plan.operations.count, privacy: .public)")

        // Phase 1: prepare (write to temp files)
        var pending: [(tempURL: URL, finalURL: URL, participantID: String, operationID: String)] = []
        do {
            for operation in plan.operations {
                if let pair = try operation.prepare() {
                    pending.append((pair.0, pair.1, operation.participantID, operation.operationID))
                }
            }
        } catch {
            // Clean up any temp files written before the failure
            for item in pending {
                try? FileManager.default.removeItem(at: item.tempURL)
            }
            Logger.vault.error("VaultCommit Phase 1 failed for \(plan.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard !pending.isEmpty else {
            Logger.vault.debug("VaultCommit nothing to commit label=\(plan.label, privacy: .public)")
            return
        }

        // Phase 2: commit (atomic rename each temp → final)
        var committed: [URL] = []
        do {
            for item in pending {
                if FileManager.default.fileExists(atPath: item.finalURL.path) {
                    _ = try FileManager.default.replaceItemAt(item.finalURL, withItemAt: item.tempURL)
                } else {
                    try FileManager.default.moveItem(at: item.tempURL, to: item.finalURL)
                }
                committed.append(item.finalURL)
                Logger.vault.debug(
                    "VaultCommit op participant=\(item.participantID, privacy: .public) op=\(item.operationID, privacy: .public)"
                )
            }
        } catch {
            // Clean up uncommitted temp files (already-committed files stay as-is)
            let committedSet = Set(committed.map { $0.path })
            for item in pending where !committedSet.contains(item.finalURL.path) {
                try? FileManager.default.removeItem(at: item.tempURL)
            }
            Logger.vault.error("VaultCommit Phase 2 partial failure for \(plan.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        Logger.vault.debug("VaultCommit complete label=\(plan.label, privacy: .public)")
    }
}
