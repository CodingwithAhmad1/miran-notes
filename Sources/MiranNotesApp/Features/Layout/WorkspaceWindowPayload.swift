import Foundation

/// Opens an additional window onto a vault with a chosen pane layout.
struct WorkspaceWindowPayload: Hashable, Codable {
    var vaultPath: String
    var initialLayout: PaneLayout
    var workspaceScope: WorkspaceScope
}
