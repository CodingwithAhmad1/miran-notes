// Tag mutations for the open note (stored in `properties["tags"]`, via `EditCommand.setProperty`).
import Foundation
import MiranNotesCore

extension AppModel {
    /// Every tag in the vault, sorted (from ``tagIndex``).
    var allVaultTags: [String] {
        Set(tagIndex.values.flatMap { $0 }).sorted()
    }

    func addTag(_ rawTag: String, pane: Int? = nil) {
        let tag = NoteTags.normalize(rawTag)
        guard !tag.isEmpty else { return }
        mutateTags(pane: pane ?? activePaneIndex) { tags in
            guard !tags.contains(tag) else { return }
            tags.append(tag)
        }
    }

    func removeTag(_ tag: String, pane: Int? = nil) {
        mutateTags(pane: pane ?? activePaneIndex) { tags in
            tags.removeAll { $0 == tag }
        }
    }

    private func mutateTags(pane: Int, _ mutate: (inout [String]) -> Void) {
        guard workspacePanes.indices.contains(pane),
              let doc = workspacePanes[pane].activeDocument else { return }
        var tags = NoteTags.parse(doc.metadata.properties)
        let before = tags
        mutate(&tags)
        guard tags != before else { return }
        if pane != activePaneIndex { activatePaneForEditingSync(pane) }
        let newDoc = apply([.setProperty(key: NoteTags.propertyKey, value: NoteTags.serialized(tags))])
        tagIndex[newDoc.metadata.noteID] = Set(NoteTags.parse(newDoc.metadata.properties))
    }
}
