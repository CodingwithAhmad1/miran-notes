import SwiftUI
import MiranNotesCore

struct WeeklyCalendarView: View {
    @ObservedObject var model: PlanningModel
    let onCreateSession: () -> Void

    private let hourRange = 6...22
    private let rowHeight: CGFloat = 40

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: model.selectedDate) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Divider()
                ZStack(alignment: .topLeading) {
                    hourGridWeekly
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 50)
            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(dayName(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.callout.weight(isToday(day) ? .bold : .regular))
                        .foregroundStyle(isToday(day) ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background(isToday(day) ? Color.accentColor : Color.clear)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected(day) ? Color.accentColor.opacity(0.08) : Color.clear)
                .onTapGesture {
                    Task { await model.selectDate(day) }
                }
            }
        }
    }

    private var hourGridWeekly: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hourRange), id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d", hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .padding(.trailing, 4)

                    ForEach(weekDays, id: \.self) { day in
                        let sessions = sessionsAt(day: day, hour: hour)
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.separator.opacity(0.3))
                                .frame(height: 0.5)

                            ForEach(sessions, id: \.id) { session in
                                weeklySessionBlock(session)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    private func weeklySessionBlock(_ session: TableRowRecord) -> some View {
        let dur = Int(session.cells["duration"] ?? "60") ?? 60
        let h = max(CGFloat(dur) / 60.0 * rowHeight, 20)
        return RoundedRectangle(cornerRadius: 3)
            .fill(sessionColor(session).opacity(0.2))
            .overlay(alignment: .topLeading) {
                Text(session.cells["title"] ?? "")
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .padding(3)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(sessionColor(session))
                    .frame(width: 2)
            }
            .frame(height: h)
            .padding(.horizontal, 1)
    }

    private func sessionsAt(day: Date, hour: Int) -> [TableRowRecord] {
        let dateStr = PlanningModel.dateString(day)
        return model.allSessions.filter { session in
            guard session.cells["date"] == dateStr,
                  let start = session.cells["startTime"],
                  let h = Int(start.split(separator: ":").first ?? "") else { return false }
            return h == hour
        }
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: model.selectedDate)
    }

    private func sessionColor(_ session: TableRowRecord) -> Color {
        switch session.cells["type"] {
        case "session": return .indigo
        case "block": return .gray
        case "habit": return .green
        case "event": return .purple
        default: return .blue
        }
    }
}
