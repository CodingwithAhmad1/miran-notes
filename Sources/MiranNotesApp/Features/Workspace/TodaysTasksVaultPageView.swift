import SwiftUI

/// Vault-root landing page: per-calendar-day checklist (see ``VaultTodaysTasksIndexStore`` / ``VaultTodaysTasksDayStore``).
struct TodaysTasksVaultPageView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    model.goToPreviousTodaysTasksDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoToPreviousTodaysTasksDay)
                .help("Previous day with tasks")

                Text(model.todaysTasksSelectedDayDisplayShort)
                    .font(.title3.monospacedDigit())
                    .frame(minWidth: 88)

                Button {
                    model.goToNextTodaysTasksDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoToNextTodaysTasksDay)
                .help("Next day with tasks")

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Today’s Tasks")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    let id = model.addTodaysTaskRow()
                    focusedTaskID = id
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Add task")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.todaysTasksItems) { row in
                        HStack(alignment: .center, spacing: 10) {
                            Button {
                                model.toggleTodaysTaskDone(id: row.id)
                            } label: {
                                Image(systemName: row.isDone ? "checkmark.square.fill" : "square")
                                    .imageScale(.large)
                                    .foregroundStyle(row.isDone ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(row.isDone ? "Mark incomplete" : "Mark complete")

                            TextField(
                                "Task",
                                text: model.bindingForTodaysTaskTitle(id: row.id)
                            )
                            .textFieldStyle(.plain)
                            .focused($focusedTaskID, equals: row.id)
                            .strikethrough(row.isDone)
                            .foregroundStyle(row.isDone ? .secondary : .primary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .onAppear {
            model.refreshTodaysTasksIfCalendarDayChanged()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshTodaysTasksIfCalendarDayChanged()
            }
        }
    }
}
