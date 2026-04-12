import SwiftUI
import MiranNotesCore

struct ZoraMigrationSheet: View {
    @ObservedObject var model: PlanningModel
    let onComplete: (String) -> Void

    @State private var zoraPath = ""
    @State private var isRunning = false
    @State private var resultText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Import from Zora Vault")
                .font(.headline)

            Text("Point to the root of your Zora Planning vault directory (the folder containing .zora, Tasks, Sessions).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                TextField("Path to Zora vault", text: $zoraPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        zoraPath = url.path
                    }
                }
            }

            if !resultText.isEmpty {
                Text(resultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Cancel") {
                    onComplete("Migration cancelled.")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Import") {
                        Task { await runMigration() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(zoraPath.isEmpty)
                }
            }
        }
        .padding()
        .frame(minWidth: 400)
    }

    private func runMigration() async {
        isRunning = true
        let zoraURL = URL(fileURLWithPath: zoraPath)
        let engine = ZoraMigrationEngine(
            zoraRoot: zoraURL,
            databaseRepo: model.databaseRepo,
            configManager: PlanningConfigManager(vaultURL: model.databaseRepo.vaultURL)
        )

        do {
            let result = try await engine.migrate()
            await model.refreshAll()
            var summary = "Imported \(result.tasksImported) tasks, \(result.sessionsImported) sessions."
            if result.configMigrated {
                summary += " Config migrated."
            }
            if !result.errors.isEmpty {
                summary += " \(result.errors.count) errors."
            }
            resultText = summary
            onComplete(summary)
        } catch {
            resultText = "Migration failed: \(error.localizedDescription)"
            isRunning = false
        }
    }
}
