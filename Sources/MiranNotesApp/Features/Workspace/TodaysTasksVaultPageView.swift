import SwiftUI

private enum TodaysTaskLineFocus: Hashable {
    case line(taskID: UUID, lineIndex: Int)
}

private let todaysTasksCheckboxColumnWidth: CGFloat = 28

/// Vault-root landing page: per-calendar-day checklist (see ``VaultTodaysTasksIndexStore`` / ``VaultTodaysTasksDayStore``).
struct TodaysTasksVaultPageView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedLine: TodaysTaskLineFocus?

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
                    focusedLine = .line(taskID: id, lineIndex: 0)
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
                        TodaysTaskRowBlock(
                            model: model,
                            row: row,
                            focusedLine: $focusedLine
                        )
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

private struct TodaysTaskRowBlock: View {
    @Bindable var model: AppModel
    let row: VaultTodaysTaskRow
    var focusedLine: FocusState<TodaysTaskLineFocus?>.Binding

    private func focusBinding(lineIndex: Int) -> Binding<Bool> {
        Binding(
            get: { focusedLine.wrappedValue == .line(taskID: row.id, lineIndex: lineIndex) },
            set: { isOn in
                if isOn {
                    focusedLine.wrappedValue = .line(taskID: row.id, lineIndex: lineIndex)
                } else if focusedLine.wrappedValue == .line(taskID: row.id, lineIndex: lineIndex) {
                    focusedLine.wrappedValue = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    model.toggleTodaysTaskDone(id: row.id)
                } label: {
                    Image(systemName: row.isDone ? "checkmark.square.fill" : "square")
                        .imageScale(.large)
                        .foregroundStyle(row.isDone ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: todaysTasksCheckboxColumnWidth)
                .accessibilityLabel(row.isDone ? "Mark incomplete" : "Mark complete")

                TodaysTaskLineTextField(
                    text: model.bindingForTodaysTaskLine(taskID: row.id, lineIndex: 0),
                    isFocused: focusBinding(lineIndex: 0),
                    isDone: row.isDone,
                    placeholder: "Task",
                    lineIndex: 0,
                    onNewLine: {
                        let newIndex = model.insertTodaysTaskLineAfter(taskID: row.id, afterIndex: 0)
                        focusedLine.wrappedValue = .line(taskID: row.id, lineIndex: newIndex)
                    },
                    onMergeDetailLineUp: {}
                )
            }

            ForEach(Array(row.lineIDs.enumerated().dropFirst()), id: \.1) { lineIndex, _ in
                HStack(alignment: .center, spacing: 10) {
                    Color.clear
                        .frame(width: todaysTasksCheckboxColumnWidth, height: 1)
                    TodaysTaskLineTextField(
                        text: model.bindingForTodaysTaskLine(taskID: row.id, lineIndex: lineIndex),
                        isFocused: focusBinding(lineIndex: lineIndex),
                        isDone: row.isDone,
                        placeholder: "",
                        lineIndex: lineIndex,
                        onNewLine: {
                            let newIndex = model.insertTodaysTaskLineAfter(taskID: row.id, afterIndex: lineIndex)
                            focusedLine.wrappedValue = .line(taskID: row.id, lineIndex: newIndex)
                        },
                        onMergeDetailLineUp: {
                            let prev = lineIndex - 1
                            model.removeTodaysTaskLine(taskID: row.id, lineIndex: lineIndex)
                            focusedLine.wrappedValue = .line(taskID: row.id, lineIndex: prev)
                        }
                    )
                }
            }
        }
    }
}
