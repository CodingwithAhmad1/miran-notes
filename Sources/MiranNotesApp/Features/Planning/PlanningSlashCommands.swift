import Foundation
import MiranNotesCore

extension SlashCommandRegistry {
    fileprivate static let slashTasksDatabaseSentinel = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    fileprivate static let slashSessionsDatabaseSentinel = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    static func registerPlanningCommands() {
        let defaultCommitPolicy: Set<SlashCommitMatch.CommitCharacter> = [.newline]

        register(SlashCommandDescriptor(
            id: "task",
            title: "Quick Task",
            category: "Planning",
            aliases: ["todo"],
            keywords: ["task", "todo", "planning", "add task"],
            preview: "Insert a task placeholder linked to the Planning database.",
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { token, tokenRange, blockID in
                let title = planningSlashTitle(from: token, commandID: "task", fallback: "New Task")
                let rowID = UUID()
                return [
                    EditCommand.replaceText(range: tokenRange, replacement: ""),
                    EditCommand.changeBlockType(blockID: blockID, type: .callout, headingLevel: nil),
                    EditCommand.replaceText(
                        range: MiranNotesCore.TextRange(start: tokenRange.start, length: 0),
                        replacement: "[ ] \(title)"
                    ),
                    EditCommand.registerDatabaseRow(databaseID: slashTasksDatabaseSentinel, rowID: rowID),
                ]
            }
        ))

        register(SlashCommandDescriptor(
            id: "session",
            title: "Quick Session",
            category: "Planning",
            aliases: [],
            keywords: ["session", "study", "planning", "calendar"],
            preview: "Insert a session placeholder linked to the Planning calendar.",
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { token, tokenRange, blockID in
                let title = planningSlashTitle(from: token, commandID: "session", fallback: "New Session")
                let rowID = UUID()
                return [
                    EditCommand.replaceText(range: tokenRange, replacement: ""),
                    EditCommand.changeBlockType(blockID: blockID, type: .callout, headingLevel: nil),
                    EditCommand.replaceText(
                        range: MiranNotesCore.TextRange(start: tokenRange.start, length: 0),
                        replacement: "📅 \(title)"
                    ),
                    EditCommand.registerDatabaseRow(databaseID: slashSessionsDatabaseSentinel, rowID: rowID),
                ]
            }
        ))
    }
}

private func planningSlashTitle(from tokenWithoutSlash: String, commandID: String, fallback: String) -> String {
    let trimmed = tokenWithoutSlash.trimmingCharacters(in: .whitespacesAndNewlines)
    let commandPrefix = "\(commandID) "
    if trimmed == commandID {
        return fallback
    }
    if trimmed.lowercased().hasPrefix(commandPrefix) {
        let title = String(trimmed.dropFirst(commandPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }
    return fallback
}
