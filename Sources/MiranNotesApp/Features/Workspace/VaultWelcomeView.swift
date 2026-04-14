import SwiftUI

/// Shown when no vault bookmark exists until the user chooses a folder (Obsidian-style).
struct VaultWelcomeView: View {
    let onOpenVault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Open a vault")
                .font(.title2)
                .fontWeight(.semibold)
            Text(
                "Choose an empty folder on your Mac, or create one in the picker. Notes and folders will be stored inside that directory."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Open…", action: onOpenVault)
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
