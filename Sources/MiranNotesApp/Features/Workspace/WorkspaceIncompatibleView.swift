import SwiftUI

struct WorkspaceIncompatibleView: View {
    let report: CompatibilityReport
    let onChooseDifferentFolder: () -> Void

    private var visibleIssues: [CompatibilityIssue] {
        Array(report.issues.prefix(WorkspaceCompatibilityPolicy.maxIssuesInUI))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Workspace not compatible")
                .font(.title2)
                .fontWeight(.semibold)
            Text(report.summary)
                .foregroundStyle(.secondary)
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
