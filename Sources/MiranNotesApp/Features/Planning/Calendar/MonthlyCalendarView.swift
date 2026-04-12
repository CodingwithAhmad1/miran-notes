import SwiftUI
import MiranNotesCore

struct MonthlyCalendarView: View {
    @ObservedObject var model: PlanningModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: model.selectedDate)
    }

    private var daysInGrid: [Date?] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: model.selectedDate) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthInterval.start)
        let daysInMonth = cal.range(of: .day, in: .month, for: model.selectedDate)?.count ?? 30

        var grid: [Date?] = Array(repeating: nil, count: (firstWeekday - cal.firstWeekday + 7) % 7)
        for day in 0..<daysInMonth {
            grid.append(cal.date(byAdding: .day, value: day, to: monthInterval.start))
        }
        while grid.count % 7 != 0 { grid.append(nil) }
        return grid
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(monthTitle)
                .font(.title3.weight(.semibold))
                .padding(.vertical, 8)

            weekdayHeaders

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCellView(date)
                    } else {
                        Color.clear
                            .frame(minHeight: 80)
                    }
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 1) {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { name in
                Text(name.prefix(2).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func dayCellView(_ date: Date) -> some View {
        let cal = Calendar.current
        let dayNum = cal.component(.day, from: date)
        let dateStr = PlanningModel.dateString(date)
        let taskCount = model.allTasks.filter { $0.cells["date"] == dateStr && $0.cells["status"] != "complete" }.count
        let sessionCount = model.allSessions.filter { $0.cells["date"] == dateStr }.count

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(dayNum)")
                    .font(.caption.weight(cal.isDateInToday(date) ? .bold : .regular))
                    .foregroundStyle(cal.isDateInToday(date) ? .white : .primary)
                    .frame(width: 22, height: 22)
                    .background(cal.isDateInToday(date) ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
                Spacer()
            }

            if sessionCount > 0 {
                HStack(spacing: 2) {
                    Circle().fill(.indigo).frame(width: 5, height: 5)
                    Text("\(sessionCount)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            if taskCount > 0 {
                HStack(spacing: 2) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                    Text("\(taskCount)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(4)
        .frame(minHeight: 80)
        .background(cal.isDate(date, inSameDayAs: model.selectedDate) ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.selectDate(date) }
        }
    }
}
