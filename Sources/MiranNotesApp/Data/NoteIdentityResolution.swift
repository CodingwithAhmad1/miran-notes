import Foundation
import MiranNotesCore

/// Canonical rules for which `noteID` wins when loading a note from disk.
///
/// **Precedence**
/// 1. Valid `.meta.json` — `noteID` comes from the sidecar (after ``MetadataSchema/migrate``).
/// 2. No usable sidecar — use ``VaultManifest`` entry for the same `relativePath` if present.
/// 3. Neither — caller allocates a new `UUID`, registers it in the manifest, and persists before loading.
///
/// **Conflict:** If sidecar and manifest disagree for the same path, **sidecar wins**; update the manifest entry’s `noteID` to match the sidecar.
enum NoteIdentityResolution {
    /// Reads and decodes `.meta.json` only (no `.txt`). Returns migrated metadata, or `nil` if missing/invalid.
    static func decodeSidecarMetadata(
        vaultRoot: URL,
        relativePath: String,
        decoder: JSONDecoder
    ) throws -> NoteMetadata? {
        try VaultPath.validateRelativePath(relativePath)
        let metaURL = VaultPath.fileURL(vaultRoot: vaultRoot, relativePathWithoutExtension: relativePath, extension: "meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let decoded = try? decoder.decode(NoteMetadata.self, from: data) else {
            return nil
        }
        return MetadataSchema.migrate(decoded)
    }

    /// If sidecar `noteID` differs from the manifest row for `relativePath`, updates manifest to the sidecar (sidecar wins).
    /// - Returns: `true` if `manifest` was mutated.
    @discardableResult
    static func alignManifestWithSidecarIfNeeded(
        manifest: inout VaultManifest,
        relativePath: String,
        sidecarNoteID: UUID,
        title: String?
    ) -> Bool {
        guard let idx = manifest.entries.firstIndex(where: { $0.relativePath == relativePath }) else {
            return false
        }
        if manifest.entries[idx].noteID == sidecarNoteID {
            return false
        }
        manifest.entries[idx].noteID = sidecarNoteID
        if let title {
            manifest.entries[idx].title = title
        }
        manifest.isDirty = true
        return true
    }
}
