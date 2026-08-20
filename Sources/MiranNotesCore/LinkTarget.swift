import Foundation

/// Target of a stored relationship (see `RelationshipIndex`). Note links are the only produced kind today;
/// folder/external cases are reserved for wiki-link targets beyond notes (`ExternalBookmarkStore`).
public enum LinkTarget: Codable, Equatable, Hashable, Sendable {
    case note(noteID: UUID)
    case folder(folderID: UUID)
    case externalFile(bookmarkID: UUID)
    case externalFolder(bookmarkID: UUID)
}

public struct LinkRelationship: Codable, Equatable, Hashable, Sendable {
    public var sourceNoteID: UUID
    public var target: LinkTarget
    public var relationshipKind: String

    public init(sourceNoteID: UUID, target: LinkTarget, relationshipKind: String) {
        self.sourceNoteID = sourceNoteID
        self.target = target
        self.relationshipKind = relationshipKind
    }
}
