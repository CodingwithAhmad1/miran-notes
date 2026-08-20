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
    @State private var isDayPickerPresented = false
    @State private var dayPickerDate = Date()

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

                Button {
                    dayPickerDate = model.todaysTasksSelectedDay.startOfDayDate(calendar: AppModel.vaultTasksCalendar()) ?? Date()
                    isDayPickerPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Text(model.todaysTasksSelectedDayDisplayShort)
                            .font(.title3.monospacedDigit())
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 88)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Jump to any day")
                .popover(isPresented: $isDayPickerPresented) {
                    DatePicker(
                        "Day",
                        selection: $dayPickerDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .onChange(of: dayPickerDate) { _, newDate in
                        let calendar = AppModel.vaultTasksCalendar()
                        let day = VaultTasksCalendarDay.today(calendar: calendar, referenceDate: newDate)
                        model.goToTodaysTasksDay(day)
                        isDayPickerPresented = false
                    }
                }

                Button {
                    model.goToNextTodaysTasksDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoToNextTodaysTasksDay)
                .help("Next day with tasks")

                if !model.todaysTasksSelectedDayIsToday {
                    Button("Today") {
                        model.goToTodaysTasksToday()
                    }
                    .controlSize(.small)
                }

                Spacer(minLength: 0)

                if model.todaysTasksRolloverSourceDay != nil {
                    Button {
                        model.rollOverIncompleteTasksIntoSelectedDay()
                    } label: {
                        Label("Roll Over", systemImage: "arrow.uturn.forward")
                    }
                    .controlSize(.small)
                    .help("Copy unfinished tasks from the last day that has any")
                }
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

    private var sourceNoteTitle: String {
        guard let id = row.sourceNoteID else { return "" }
        return model.noteSummaries.first(where: { $0.noteID == id })?.title ?? "Missing note"
    }

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

            if row.sourceNoteID != nil || row.rolledFromDayKey != nil {
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: todaysTasksCheckboxColumnWidth, height: 1)
                    if row.sourceNoteID != nil {
                        Button {
                            model.openTodaysTaskSource(row)
                        } label: {
                            Label(sourceNoteTitle, systemImage: "doc.text")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Open the note this task came from")
                        .contextMenu {
                            Button("Open in Note") {
                                model.openTodaysTaskSource(row)
                            }
                            if !row.isDone, row.sourceBlockID != nil {
                                Button("Mark Done in Note Too") {
                                    model.toggleTodaysTaskDone(id: row.id)
                                    model.markTodaysTaskDoneInSourceNote(row)
                                }
                            }
                        }
                    }
                    if let rolledKey = row.rolledFromDayKey {
                        Label("from \(rolledKey)", systemImage: "arrow.uturn.forward")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
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
