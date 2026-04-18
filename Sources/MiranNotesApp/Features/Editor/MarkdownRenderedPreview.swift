import AppKit
import SwiftUI

/// Read-only rendered markdown using `AttributedString` (GFM tables may render partially depending on OS).
struct MarkdownRenderedPreview: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            ScrollView {
                Group {
                    if let attributed = try? AttributedString(
                        markdown: source,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full),
                        baseURL: nil
                    ) {
                        Text(attributed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text(source)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
