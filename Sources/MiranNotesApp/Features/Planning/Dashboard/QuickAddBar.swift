import SwiftUI
import MiranNotesCore

struct QuickAddBar: View {
    @ObservedObject var model: PlanningModel
    @State private var title = ""
    @State private var showingDetail = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("Quick add task...", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task {
                        await model.quickAddTask(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: model.config.quickAddDefaults.defaultType,
                            priority: model.config.quickAddDefaults.defaultPriority
                        )
                        title = ""
                    }
                }

            Button {
                showingDetail = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDetail) {
                TaskEditSheet(model: model, mode: .create) {
                    showingDetail = false
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
