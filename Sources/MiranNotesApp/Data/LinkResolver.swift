import Foundation
import MiranNotesCore

struct LinkResolver {
    private let manifest: VaultManifest

    init(manifest: VaultManifest) {
        self.manifest = manifest
    }

    /// Resolves a link target to the current `baseName`, if the note exists in the manifest.
    func baseName(forTargetNoteID id: UUID) -> String? {
        manifest.entry(noteID: id)?.baseName
    }

    func noteID(forBaseName baseName: String) -> UUID? {
        manifest.entry(baseName: baseName)?.noteID
    }
}
