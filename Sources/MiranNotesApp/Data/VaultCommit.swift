import Foundation
import MiranNotesCore
import os.log

struct VaultCommitOperation {
    let participantID: String
    let operationID: String
    let execute: () throws -> Void
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
    let encoder: JSONEncoder
    let manifest: VaultManifest
    let linkGraph: LinkGraph
    let atomicWrite: (Data, URL) throws -> Void
}

struct VaultCommitCoordinator {
    func execute(_ plan: VaultCommitPlan) throws {
        guard !plan.operations.isEmpty else { return }
        Logger.vault.debug("VaultCommit begin label=\(plan.label, privacy: .public) ops=\(plan.operations.count, privacy: .public)")
        for operation in plan.operations {
            try operation.execute()
            Logger.vault.debug(
                "VaultCommit op participant=\(operation.participantID, privacy: .public) op=\(operation.operationID, privacy: .public)"
            )
        }
        Logger.vault.debug("VaultCommit complete label=\(plan.label, privacy: .public)")
    }
}
