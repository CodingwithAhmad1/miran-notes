import Foundation
import MiranNotesCore

/// Post-commit checks for vault-wide consistency (fast path; runs after persistence, not per keystroke).
struct VaultIntegrityResult: Equatable, Sendable {
    var issues: [String]

    var isClean: Bool { issues.isEmpty }

    static let clean = VaultIntegrityResult(issues: [])
}

enum VaultIntegrityChecker {
    /// Validates manifest paths, link graph targets, relationship note targets, and optional on-disk note payload.
    static func check(
        vaultURL: URL,
        manifest: VaultManifest,
        linkGraph: LinkGraph,
        relationshipIndex: RelationshipIndex,
        savedNoteRelativePath: String?,
        decoder: JSONDecoder
    ) -> VaultIntegrityResult {
        var issues: [String] = []
        let fm = FileManager.default
        let noteIDs = Set(manifest.entries.map(\.noteID))

        for entry in manifest.entries {
            let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: entry.relativePath, extension: "txt")
            if !fm.fileExists(atPath: txt.path) {
                issues.append("Manifest lists a note with no text file at \(entry.relativePath).")
            }
        }

        for (source, targets) in linkGraph.outgoing {
            if noteIDs.contains(source) == false {
                issues.append("Link graph references unknown source note \(source.uuidString).")
            }
            for t in targets where !noteIDs.contains(t) {
                issues.append("Link graph lists a link to a missing note \(t.uuidString).")
            }
        }

        for rel in relationshipIndex.relationships {
            if !noteIDs.contains(rel.sourceNoteID) {
                issues.append("Relationship index references unknown source note \(rel.sourceNoteID.uuidString).")
            }
            switch rel.target {
            case .note(let id):
                if !noteIDs.contains(id) {
                    issues.append("Relationship index references unknown target note \(id.uuidString).")
                }
            case .artifact(let nid, _, _):
                if !noteIDs.contains(nid) {
                    issues.append("Relationship index references unknown note for artifact \(nid.uuidString).")
                }
            case .folder, .externalFile, .externalFolder:
                break
            }
        }

        if let relPath = savedNoteRelativePath {
            let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "txt")
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "meta.json")
            guard fm.fileExists(atPath: textURL.path), fm.fileExists(atPath: metaURL.path) else {
                issues.append("Saved note files are missing on disk after commit.")
                return VaultIntegrityResult(issues: issues)
            }
            let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(NoteMetadata.self, from: data) else {
                issues.append("Could not read note metadata after save.")
                return VaultIntegrityResult(issues: issues)
            }
            let migrated = MetadataSchema.migrate(meta)
            let doc = NoteDocument(text: text, metadata: migrated)
            let report = NoteIntegrity.check(document: doc)
            if !report.isValid {
                issues.append("Saved note failed structural validation after commit.")
            }
        }

        return VaultIntegrityResult(issues: issues)
    }
}
