import MiranNotesCore

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

/// State for one non-active (read-only) view pane.
struct ViewPaneState: Equatable {
    /// Manifest relative path of the note displayed in this pane (nil = empty placeholder).
    var noteBaseName: String?
    /// Loaded document for read-only display. Nil when no note is selected or load is pending.
    var document: NoteDocument?
}
