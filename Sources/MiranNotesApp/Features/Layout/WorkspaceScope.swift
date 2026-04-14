import Foundation

/// Scopes the workspace shell (e.g. sidebar) to a subtree of the vault folder tree.
enum WorkspaceScope: Equatable, Hashable, Codable {
    case fullVault
    case folderSubtree(rootFolderID: UUID)
}
