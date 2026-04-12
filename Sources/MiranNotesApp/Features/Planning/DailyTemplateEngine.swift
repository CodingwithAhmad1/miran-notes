import Foundation
import MiranNotesCore

/// Generates daily note content from a template string and the day's planning data.
enum DailyTemplateEngine {
    static func render(
        template: String,
        date: Date,
        tasks: [TableRowRecord],
        sessions: [TableRowRecord]
    ) -> String {
        let dateStr = DatabaseDateParser.formatLoose(date)

        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let fullDate = formatter.string(from: date)

        var result = template
            .replacingOccurrences(of: "{{date}}", with: fullDate)
            .replacingOccurrences(of: "{{date_short}}", with: dateStr)

        let sessionLines = sessions.map { session in
            let time = session.cells["startTime"] ?? ""
            let title = session.cells["title"] ?? ""
            let subject = session.cells["subject"] ?? ""
            let dur = session.cells["duration"] ?? ""
            var line = "- "
            if !time.isEmpty { line += "[\(time)] " }
            line += title
            if !subject.isEmpty { line += " (\(subject))" }
            if !dur.isEmpty { line += " — \(dur)min" }
            return line
        }
        result = result.replacingOccurrences(
            of: "{{sessions}}",
            with: sessionLines.isEmpty ? "_No sessions_" : sessionLines.joined(separator: "\n")
        )

        let taskLines = tasks.map { task in
            let status = task.cells["status"] == "complete" ? "[x]" : "[ ]"
            let title = task.cells["title"] ?? ""
            let priority = task.cells["priority"] ?? ""
            var line = "- \(status) \(title)"
            if !priority.isEmpty { line += " [\(priority)]" }
            return line
        }
        result = result.replacingOccurrences(
            of: "{{tasks}}",
            with: taskLines.isEmpty ? "_No tasks_" : taskLines.joined(separator: "\n")
        )

        return result
    }
}
