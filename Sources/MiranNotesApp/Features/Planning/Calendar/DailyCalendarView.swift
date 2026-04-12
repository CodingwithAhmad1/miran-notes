import SwiftUI
import MiranNotesCore

struct DailyCalendarView: View {
    @ObservedObject var model: PlanningModel
    let onCreateSession: () -> Void

    private let hourRange = 6...23
    private let rowHeight: CGFloat = 48

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                unscheduledRow
                Divider()

                ZStack(alignment: .topLeading) {
                    hourGrid
                    sessionBlocks
                    nowIndicator
                }
            }
        }
    }

    private var unscheduledRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unscheduled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 56)

            let unscheduled = model.todayTasks.filter { ($0.cells["time"] ?? "").isEmpty }
            if unscheduled.isEmpty {
                Text("No unscheduled tasks")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 56)
            } else {
                ForEach(unscheduled, id: \.id) { task in
                    HStack {
                        Spacer().frame(width: 56)
                        Text(task.cells["title"] ?? "")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hourRange), id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                        .padding(.trailing, 4)

                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                        .padding(.top, 6)
                }
                .frame(height: rowHeight)
            }
        }
    }

    private var sessionBlocks: some View {
        ForEach(model.todaySessions, id: \.id) { session in
            if let start = session.cells["startTime"],
               let yOffset = yOffset(for: start) {
                let dur = Int(session.cells["duration"] ?? "60") ?? 60
                let blockHeight = CGFloat(dur) / 60.0 * rowHeight

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(sessionColor(session).opacity(0.15))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(sessionColor(session))
                                .frame(width: 3)
                        }
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.cells["title"] ?? "")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let subj = session.cells["subject"], !subj.isEmpty {
                                    Text(subj)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: max(blockHeight, 24))
                }
                .padding(.leading, 56)
                .padding(.trailing, 8)
                .offset(y: yOffset)
            }
        }
    }

    @ViewBuilder
    private var nowIndicator: some View {
        let cal = Calendar.current
        if cal.isDate(model.selectedDate, inSameDayAs: Date()) {
            let comps = cal.dateComponents([.hour, .minute], from: Date())
            let hour = comps.hour ?? 0
            let minute = comps.minute ?? 0
            if hourRange.contains(hour) {
                let y = CGFloat(hour - hourRange.lowerBound) * rowHeight + CGFloat(minute) / 60.0 * rowHeight

                HStack(spacing: 0) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Rectangle().fill(.red).frame(height: 1)
                }
                .padding(.leading, 48)
                .offset(y: y)
            }
        }
    }

    private func yOffset(for time: String) -> CGFloat? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        guard hourRange.contains(h) else { return nil }
        return CGFloat(h - hourRange.lowerBound) * rowHeight + CGFloat(m) / 60.0 * rowHeight
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
