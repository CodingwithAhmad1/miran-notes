import SwiftUI

struct WorkspaceIncompatibleView: View {
    let report: CompatibilityReport
    let onChooseDifferentFolder: () -> Void

    private var visibleIssues: [CompatibilityIssue] {
        Array(report.issues.prefix(WorkspaceCompatibilityPolicy.maxIssuesInUI))
    }

    private var hasMixedBodyExtensions: Bool {
        report.issues.contains { $0.code == .mixedNoteBodyExtensionsInFolder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Workspace not compatible")
                .font(.title2)
                .fontWeight(.semibold)
            Text(report.summary)
                .foregroundStyle(.secondary)
            if hasMixedBodyExtensions {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fixing mixed .txt / .md in one folder")
                        .font(.headline)
                    Text(
                        """
                        Miran allows only one note body format per folder (and at the vault root). To import markdown:

                        • Move `.md` files into a **new topic folder** used only for markdown, or
                        • Convert imports to `.txt` so they match the rest of that folder.

                        See **ImportingNotes** in the project docs for the full workspace layout rules.
                        """
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !visibleIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.message)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let path = issue.path {
                                    Text(path.posixPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Button("Choose Different Folder…", action: onChooseDifferentFolder)
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 280)
    }
}
