/// The arrangement of note panes in the editor area.
enum PaneLayout: Int, CaseIterable, Equatable {
    case single
    case twoPane
    case threePane
    case fourPane

    /// Total number of panes in this layout (including the active/editable pane).
    var paneCount: Int {
        switch self {
        case .single: return 1
        case .twoPane: return 2
        case .threePane: return 3
        case .fourPane: return 4
        }
    }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .twoPane: return "Two-Note Split"
        case .threePane: return "Three-Note Split"
        case .fourPane: return "Four-Note Split"
        }
    }
}
