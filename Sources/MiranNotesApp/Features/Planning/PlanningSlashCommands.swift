import Foundation
import MiranNotesCore

extension SlashCommandRegistry {
    static func registerPlanningCommands() {
        let defaultCommitPolicy: Set<SlashCommitMatch.CommitCharacter> = [.space, .newline]

        register(SlashCommandDescriptor(
            id: "task",
            title: "Quick Task",
            category: "Planning",
            aliases: ["todo"],
            keywords: ["task", "todo", "planning", "add task"],
            preview: "Insert a task placeholder linked to the Planning database.",
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .callout, headingLevel: nil),
                    .replaceText(
                        range: MiranNotesCore.TextRange(start: tokenRange.start, length: 0),
                        replacement: "[ ] "
                    ),
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
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .callout, headingLevel: nil),
                    .replaceText(
                        range: MiranNotesCore.TextRange(start: tokenRange.start, length: 0),
                        replacement: "📅 "
                    ),
                ]
            }
        ))
    }
}
