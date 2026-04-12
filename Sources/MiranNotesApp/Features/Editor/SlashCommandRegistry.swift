import Foundation
import MiranNotesCore

private struct SlashCommandDescriptor {
    let id: String
    let aliases: Set<String>
    let commitPolicy: Set<SlashCommitMatch.CommitCharacter>
    let applicability: Set<BlockType>?
    let produce: (_ tokenWithoutSlash: String, _ tokenRange: MiranNotesCore.TextRange, _ blockID: String) -> [EditCommand]?

    func matchesToken(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == id || aliases.contains(tokenWithoutSlash)
    }

    func accepts(match: SlashCommitMatch, blockType: BlockType?) -> Bool {
        guard commitPolicy.contains(match.commitCharacter) else { return false }
        guard let applicability else { return true }
        guard let blockType else { return false }
        return applicability.contains(blockType)
    }
}

/// Built-in slash commands with deterministic descriptor ordering.
enum SlashCommandRegistry {
    static func editCommands(for match: SlashCommitMatch, blockID: String, blockType: BlockType? = nil) -> [EditCommand]? {
        let tokenRange = MiranNotesCore.TextRange(
            start: match.lineStartUTF16,
            length: match.commitUTF16Index - match.lineStartUTF16
        )
        let token = match.tokenWithoutSlash

        guard
            let descriptor = descriptors.first(where: { $0.matchesToken(token) && $0.accepts(match: match, blockType: blockType) })
        else { return nil }

        return descriptor.produce(token, tokenRange, blockID)
    }

    private static let defaultCommitPolicy: Set<SlashCommitMatch.CommitCharacter> = [.space, .newline]

    // Ordered by precedence: first match wins.
    private static let descriptors: [SlashCommandDescriptor] = [
        SlashCommandDescriptor(
            id: "h1",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .heading, headingLevel: 1)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "h2",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .heading, headingLevel: 2)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "h3",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .heading, headingLevel: 3)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "p",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .paragraph, headingLevel: nil)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "code",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .code, headingLevel: nil)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "list",
            aliases: ["bullet"],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .listItem, headingLevel: nil)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "divider",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .divider, headingLevel: nil)
                ]
            }
        ),
        SlashCommandDescriptor(
            id: "callout",
            aliases: [],
            commitPolicy: defaultCommitPolicy,
            applicability: nil,
            produce: { _, tokenRange, blockID in
                [
                    .replaceText(range: tokenRange, replacement: ""),
                    .changeBlockType(blockID: blockID, type: .callout, headingLevel: nil)
                ]
            }
        )
    ]
}
