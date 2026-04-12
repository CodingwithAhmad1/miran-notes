import Foundation
import MiranNotesCore

/// Predefined database schemas for the Miran Planning feature.
enum PlanningSchemas {
    static func tasksSchema() -> DatabaseSchema {
        DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title", type: .string, required: true),
            DatabaseColumnDefinition(id: "type", title: "Type", type: .select, options: ["academics", "personal", "admin"], required: true),
            DatabaseColumnDefinition(id: "subject", title: "Subject", type: .select, options: []),
            DatabaseColumnDefinition(id: "date", title: "Date", type: .date, required: true),
            DatabaseColumnDefinition(id: "time", title: "Time", type: .string),
            DatabaseColumnDefinition(id: "duration", title: "Duration", type: .duration),
            DatabaseColumnDefinition(id: "priority", title: "Priority", type: .select, options: ["low", "medium", "high"]),
            DatabaseColumnDefinition(id: "status", title: "Status", type: .select, options: ["open", "complete"], required: true),
            DatabaseColumnDefinition(id: "linkedNote", title: "Linked Note", type: .noteLink),
            DatabaseColumnDefinition(id: "project", title: "Project", type: .string),
        ])
    }

    static func sessionsSchema() -> DatabaseSchema {
        DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title", type: .string, required: true),
            DatabaseColumnDefinition(id: "type", title: "Type", type: .select, options: ["session", "block", "habit", "event"], required: true),
            DatabaseColumnDefinition(id: "subject", title: "Subject", type: .select, options: []),
            DatabaseColumnDefinition(id: "topic", title: "Topic", type: .string),
            DatabaseColumnDefinition(id: "sessionType", title: "Session Type", type: .select, options: ["learning", "practice"]),
            DatabaseColumnDefinition(id: "date", title: "Date", type: .date, required: true),
            DatabaseColumnDefinition(id: "startTime", title: "Start Time", type: .string),
            DatabaseColumnDefinition(id: "duration", title: "Duration", type: .duration),
            DatabaseColumnDefinition(id: "objective", title: "Objective", type: .string),
            DatabaseColumnDefinition(id: "status", title: "Status", type: .select, options: ["planned", "complete", "missed", "partial"], required: true),
            DatabaseColumnDefinition(id: "linkedNote", title: "Linked Note", type: .noteLink),
        ])
    }

    static func tasksDefaultView() -> DatabaseViewConfig {
        DatabaseViewConfig(
            name: "All Tasks",
            layout: .table,
            sortKeys: [
                DatabaseSortKey(columnID: "date", ascending: true),
                DatabaseSortKey(columnID: "priority", ascending: false),
            ]
        )
    }

    static func tasksCalendarView() -> DatabaseViewConfig {
        DatabaseViewConfig(
            name: "Calendar",
            layout: .calendar,
            calendarDateColumnID: "date"
        )
    }

    static func sessionDefaultView() -> DatabaseViewConfig {
        DatabaseViewConfig(
            name: "All Sessions",
            layout: .table,
            sortKeys: [
                DatabaseSortKey(columnID: "date", ascending: true),
                DatabaseSortKey(columnID: "startTime", ascending: true),
            ]
        )
    }

    static func sessionCalendarView() -> DatabaseViewConfig {
        DatabaseViewConfig(
            name: "Calendar",
            layout: .calendar,
            calendarDateColumnID: "date"
        )
    }
}
