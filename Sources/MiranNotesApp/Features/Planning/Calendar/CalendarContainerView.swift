import SwiftUI
import MiranNotesCore

enum CalendarViewMode: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case review = "Review"
}

struct CalendarContainerView: View {
    @ObservedObject var model: PlanningModel
    @State private var viewMode: CalendarViewMode = .weekly
    @State private var showingCreationSheet = false

    var body: some View {
        VStack(spacing: 0) {
            calendarToolbar
            Divider()

            switch viewMode {
            case .daily:
                DailyCalendarView(model: model, onCreateSession: { showingCreationSheet = true })
            case .weekly:
                WeeklyCalendarView(model: model, onCreateSession: { showingCreationSheet = true })
            case .monthly:
                MonthlyCalendarView(model: model)
            case .review:
                WeeklyReviewView(model: model)
            }
        }
        .sheet(isPresented: $showingCreationSheet) {
            SessionEditSheet(model: model, mode: .create(prefillDate: model.selectedDate)) {
                showingCreationSheet = false
            }
        }
    }

    private var calendarToolbar: some View {
        HStack {
            Button { navigateBack() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("View", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            Button { navigateForward() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Button("Today") {
                Task { await model.selectDate(Date()) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func navigateBack() {
        Task {
            switch viewMode {
            case .daily:
                await model.navigateDay(-1)
            case .weekly:
                await model.navigateDay(-7)
            case .monthly:
                if let d = Calendar.current.date(byAdding: .month, value: -1, to: model.selectedDate) {
                    await model.selectDate(d)
                }
            case .review:
                await model.navigateDay(-7)
            }
        }
    }

    private func navigateForward() {
        Task {
            switch viewMode {
            case .daily:
                await model.navigateDay(1)
            case .weekly:
                await model.navigateDay(7)
            case .monthly:
                if let d = Calendar.current.date(byAdding: .month, value: 1, to: model.selectedDate) {
                    await model.selectDate(d)
                }
            case .review:
                await model.navigateDay(7)
            }
        }
    }
}
