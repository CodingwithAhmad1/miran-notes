import SwiftUI

/// Match navigation and replace controls, shown under the note header while the pane's
/// "Find in note…" query is non-empty. Replacement flows through `EditCommand` batches
/// (`AppModel+Find`), so replace-all is one undo step.
struct NoteFindBarView: View {
    @Bindable var model: AppModel
    var paneIndex: Int
    @State private var replacementText = ""

    private var query: String {
        guard model.workspacePanes.indices.contains(paneIndex) else { return "" }
        return model.workspacePanes[paneIndex].editorFindQuery
    }

    var body: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = model.findMatches(forPane: paneIndex)
            HStack(spacing: 8) {
                Text(matches.isEmpty
                    ? String(localized: "No matches", comment: "Find bar: zero matches")
                    : String(
                        localized: "\(model.currentFindMatchOrdinal(forPane: paneIndex, matches: matches)) of \(matches.count)",
                        comment: "Find bar: current match position"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .leading)

                Button {
                    model.findPrevious(pane: paneIndex)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(matches.isEmpty)
                .help("Previous match")

                Button {
                    model.findNext(pane: paneIndex)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(matches.isEmpty)
                .help("Next match")

                Divider().frame(height: 14)

                TextField(String(localized: "Replace with…", comment: "Find bar: replacement field"), text: $replacementText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 200)
                    .onSubmit {
                        model.replaceCurrentFindMatch(with: replacementText, pane: paneIndex)
                    }

                Button(String(localized: "Replace", comment: "Find bar: replace one")) {
                    model.replaceCurrentFindMatch(with: replacementText, pane: paneIndex)
                }
                .controlSize(.small)
                .disabled(matches.isEmpty)

                Button(String(localized: "All", comment: "Find bar: replace all")) {
                    model.replaceAllFindMatches(with: replacementText, pane: paneIndex)
                }
                .controlSize(.small)
                .disabled(matches.isEmpty)
                .help("Replace all matches (one undo step)")

                Spacer()

                Button {
                    model.workspacePanes[paneIndex].editorFindQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close find")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.thinMaterial)
        }
    }
}
