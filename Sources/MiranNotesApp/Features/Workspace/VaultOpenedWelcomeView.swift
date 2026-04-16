import SwiftUI

/// One-time welcome in the detail pane after a vault is opened; shows vault path and invites the user to use the sidebar.
struct VaultOpenedWelcomeView: View {
    let vaultPath: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(
                    "You are all set. Add folders and notes from the sidebar, or open an existing folder to see its notes here."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Vault location")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(verbatim: vaultPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: 560)

                Text("Select a folder in the list on the left to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
