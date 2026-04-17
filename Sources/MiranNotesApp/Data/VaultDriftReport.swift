import Foundation
import MiranNotesCore

struct VaultDriftReport: Sendable, Equatable {
    /// `.meta.json` paths (relative, no extension stem path like `folder/note`) where `.txt` is missing.
    var orphanMetaRelativePaths: [String]
    /// `.txt` notes on disk with no manifest entry.
    var txtRelativePathsMissingFromManifest: [String]
    /// Same `noteID` appears in more than one sidecar.
    var duplicateNoteIDsInSidecars: [VaultDuplicateNoteIDIssue]
    /// Human-readable path index vs manifest inconsistencies.
    var pathIndexManifestMismatches: [String]
}

struct VaultDuplicateNoteIDIssue: Sendable, Equatable {
    var noteID: UUID
    var relativePaths: [String]
}

enum VaultDriftValidator {
    static func validate(
        vaultURL: URL,
        manifest: VaultManifest,
        pathIndex: PathIndex,
        txtPathsOnDisk: [String]
    ) -> VaultDriftReport {
        let manifestByPath = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.relativePath, $0) })
        let manifestByID = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.noteID, $0) })

        var txtMissingFromManifest: [String] = []
        for p in txtPathsOnDisk where manifestByPath[p] == nil {
            txtMissingFromManifest.append(p)
        }
        txtMissingFromManifest.sort()

        var mismatches: [String] = []
        for entry in pathIndex.entries {
            if let man = manifestByID[entry.noteID] {
                if man.relativePath != entry.relativePath {
                    mismatches.append(
                        "noteID \(entry.noteID): path index path=\(entry.relativePath) manifest path=\(man.relativePath)"
                    )
                }
            } else {
                mismatches.append("noteID \(entry.noteID): in path index but not in manifest (path=\(entry.relativePath))")
            }
        }
        for entry in manifest.entries {
            if pathIndex.entries.contains(where: { $0.noteID == entry.noteID && $0.relativePath == entry.relativePath }) {
                continue
            }
            if !pathIndex.entries.contains(where: { $0.noteID == entry.noteID }) {
                mismatches.append("noteID \(entry.noteID): in manifest but missing from path index (path=\(entry.relativePath))")
            }
        }
        mismatches.sort()

        var idToPaths: [UUID: [String]] = [:]
        let fm = FileManager.default
        var orphanMeta: [String] = []
        if let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let item as URL in enumerator {
                let name = item.lastPathComponent.lowercased()
                guard name.hasSuffix(".meta.json") else { continue }
                               guard let rel = relativePathForMetaSidecar(vaultURL: vaultURL, metaFileURL: item) else { continue }
                let txtURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "txt")
                let mdURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "md")
                if !fm.fileExists(atPath: txtURL.path), !fm.fileExists(atPath: mdURL.path) {
                    orphanMeta.append(rel)
                }
                if let data = try? Data(contentsOf: item),
                   let meta = try? JSONDecoder().decode(NoteMetadata.self, from: data) {
                    idToPaths[meta.noteID, default: []].append(rel)
                }
            }
        }
        orphanMeta.sort()

        var dups: [VaultDuplicateNoteIDIssue] = []
        for (nid, paths) in idToPaths where Set(paths).count > 1 {
            dups.append(VaultDuplicateNoteIDIssue(noteID: nid, relativePaths: Array(Set(paths)).sorted()))
        }
        dups.sort { $0.noteID.uuidString < $1.noteID.uuidString }

        return VaultDriftReport(
            orphanMetaRelativePaths: orphanMeta,
            txtRelativePathsMissingFromManifest: txtMissingFromManifest,
            duplicateNoteIDsInSidecars: dups,
            pathIndexManifestMismatches: mismatches
        )
    }

    private static func relativePathForMetaSidecar(vaultURL: URL, metaFileURL: URL) -> String? {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = metaFileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath) else { return nil }
        var sub = String(filePath.dropFirst(vaultPath.count))
        if sub.hasPrefix("/") { sub.removeFirst() }
        let lower = sub.lowercased()
        guard lower.hasSuffix(".meta.json") else { return nil }
        sub = String(sub.dropLast(".meta.json".count))
        let parts = sub.split(separator: "/").map(String.init)
        if parts.contains(".miran") || parts.contains("_aux") { return nil }
        if let first = parts.first, VaultPath.reservedTopLevel.contains(first) { return nil }
        return sub
    }
}
