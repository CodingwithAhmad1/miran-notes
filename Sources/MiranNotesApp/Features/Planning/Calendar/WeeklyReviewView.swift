import SwiftUI
import MiranNotesCore

struct WeeklyReviewView: View {
    @ObservedObject var model: PlanningModel
    @State private var metrics: WeeklyReviewMetrics?

    private var weekRangeString: String {
        guard let m = metrics else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = f.string(from: m.weekRange.start)
        let end = f.string(from: m.weekRange.end.addingTimeInterval(-1))
        return "\(start) - \(end)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let m = metrics {
                    Text("Week of \(weekRangeString)")
                        .font(.title3.weight(.semibold))
                        .padding(.bottom, 4)

                    summaryCards(m)
                    sessionBreakdown(m)
                    timeBreakdown(m)
                } else {
                    ProgressView("Loading review...")
                }
            }
            .padding()
        }
        .task { await loadMetrics() }
    }

    private func loadMetrics() async {
        metrics = await model.weeklyReviewMetrics(weekOf: model.selectedDate)
    }

    private func summaryCards(_ m: WeeklyReviewMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(
                title: "Sessions",
                value: "\(m.sessionsCompleted)/\(m.sessionsPlanned)",
                subtitle: rateString(m.completionRate),
                color: .indigo
            )
            metricCard(
                title: "Tasks",
                value: "\(m.tasksCompleted)/\(m.tasksTotal)",
                subtitle: rateString(m.taskCompletionRate),
                color: .orange
            )
            metricCard(
                title: "Backlog",
                value: "\(m.backlogSize)",
                subtitle: m.backlogSize == 0 ? "Clear" : "overdue",
                color: m.backlogSize == 0 ? .green : .red
            )
        }
    }

    private func sessionBreakdown(_ m: WeeklyReviewMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions by Subject")
                .font(.subheadline.weight(.semibold))

            ForEach(m.sessionsBySubject.sorted(by: { $0.key < $1.key }), id: \.key) { subject, metric in
                HStack {
                    Text(subject)
                        .font(.callout)
                    Spacer()
                    Text("\(metric.completed)/\(metric.planned)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    let rate = metric.planned > 0 ? Double(metric.completed) / Double(metric.planned) : 0
                    progressBar(rate)
                        .frame(width: 60)
                }
            }
        }
    }

    private func timeBreakdown(_ m: WeeklyReviewMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Spent by Subject")
                .font(.subheadline.weight(.semibold))

            ForEach(m.timeBySubject.sorted(by: { $0.value > $1.value }), id: \.key) { subject, minutes in
                HStack {
                    Text(subject)
                        .font(.callout)
                    Spacer()
                    Text(formatDuration(minutes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if m.timeBySubject.isEmpty {
                Text("No completed sessions yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func progressBar(_ rate: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.green)
                    .frame(width: geo.size.width * CGFloat(rate))
            }
        }
        .frame(height: 6)
    }

    private func rateString(_ rate: Double) -> String {
        "\(Int(rate * 100))%"
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
