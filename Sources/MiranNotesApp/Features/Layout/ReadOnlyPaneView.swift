import MiranNotesCore
import SwiftUI

/// A non-editable pane showing a loaded note or an empty placeholder.
///
/// Tapping this pane calls `onActivate`, making it the editable pane in the layout.
/// After activation, the user selects a note from the main sidebar as usual.
///
/// - Note: Rich/wikilink rendering is not implemented here. Plain text is displayed.
///   TODO: replace with attributed NSTextView rendering matching the active editor.
struct ReadOnlyPaneView: View {
    /// The current state for this view pane slot.
    let state: ViewPaneState
    /// Whether this pane is the focused/active one (used only when no note is loaded, to drive styling).
    let isActive: Bool
    /// Called when the user taps the pane to activate it.
    let onActivate: () -> Void

    var body: some View {
        ZStack {
            if let document = state.document {
                noteContentView(document: document)
            } else {
                placeholderView
            }
        }
        .overlay(alignment: .topLeading) {
            // Subtle highlight ring when this is the active (editable) pane.
            if isActive {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
    }

    // MARK: - Note content

    private func noteContentView(document: NoteDocument) -> some View {
        ScrollView(.vertical) {
            Text(document.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No note open")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Click to activate this pane, then select a note from the sidebar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
