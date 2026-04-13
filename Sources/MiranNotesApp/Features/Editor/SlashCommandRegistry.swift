import Foundation
import MiranNotesCore

struct SlashCommandCatalogItem: Equatable, Identifiable {
    let id: String
    let title: String
    let category: String
    let aliases: [String]
    let keywords: [String]
    let preview: String
}

/// Descriptor for a single slash command. `internal` so feature modules in the same package can register custom descriptors.
struct SlashCommandDescriptor {
    let id: String
    let title: String
    let category: String
    let aliases: Set<String>
    let keywords: [String]
    let preview: String
    let commitPolicy: Set<SlashCommitMatch.CommitCharacter>
    let applicability: Set<BlockType>?
    let produce: (_ tokenWithoutSlash: String, _ tokenRange: MiranNotesCore.TextRange, _ blockID: String) -> [EditCommand]?

    func matchesToken(_ tokenWithoutSlash: String) -> Bool {
        let command = Self.commandToken(from: tokenWithoutSlash)
        return command == id || aliases.contains(command)
    }

    static func commandToken(from tokenWithoutSlash: String) -> String {
        tokenWithoutSlash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased() ?? ""
    }

    func accepts(match: SlashCommitMatch, blockType: BlockType?) -> Bool {
        guard commitPolicy.contains(match.commitCharacter) else { return false }
        guard let applicability else { return true }
        guard let blockType else { return false }
        return applicability.contains(blockType)
    }

    var catalogItem: SlashCommandCatalogItem {
        SlashCommandCatalogItem(
            id: id,
            title: title,
            category: category,
            aliases: aliases.sorted(),
            keywords: keywords,
            preview: preview
        )
    }
}

/// Slash command registry with open registration so feature modules can add commands at startup.
@MainActor
enum SlashCommandRegistry {
    private static var descriptors: [SlashCommandDescriptor] = []
    private static var builtinsRegistered = false

    /// Register all built-in commands. Called once from app startup via `MiranNotesApp.init`.
    static func registerBuiltins() {
        guard !builtinsRegistered else { return }
        builtinsRegistered = true
        let builtins: [SlashCommandDescriptor] = [
            .init(
                id: "h1",
                title: "Heading 1",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["title", "header", "large"],
                preview: "Turn text into a large heading.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .heading, headingLevel: 1)
                    ]
                }
            ),
            .init(
                id: "h2",
                title: "Heading 2",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["subtitle", "header", "medium"],
                preview: "Turn text into a medium heading.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .heading, headingLevel: 2)
                    ]
                }
            ),
            .init(
                id: "h3",
                title: "Heading 3",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["subheading", "header", "small"],
                preview: "Turn text into a small heading.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .heading, headingLevel: 3)
                    ]
                }
            ),
            .init(
                id: "p",
                title: "Text",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["paragraph", "body", "normal"],
                preview: "Turn text into a normal paragraph.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .paragraph, headingLevel: nil)
                    ]
                }
            ),
            .init(
                id: "code",
                title: "Code",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["snippet", "monospace", "programming"],
                preview: "Turn text into a code block.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .code, headingLevel: nil)
                    ]
                }
            ),
            .init(
                id: "list",
                title: "Bulleted List",
                category: "Lists",
                aliases: ["bullet"],
                keywords: ["bullets", "unordered", "list item"],
                preview: "Turn text into a bulleted list item.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .listItem, headingLevel: nil)
                    ]
                }
            ),
            .init(
                id: "divider",
                title: "Divider",
                category: "Layout",
                aliases: [],
                keywords: ["horizontal rule", "separator", "line"],
                preview: "Insert a visual divider block.",
                commitPolicy: defaultCommitPolicy,
                applicability: nil,
                produce: { _, tokenRange, blockID in
                    [
                        .replaceText(range: tokenRange, replacement: ""),
                        .changeBlockType(blockID: blockID, type: .divider, headingLevel: nil)
                    ]
                }
            ),
            .init(
                id: "callout",
                title: "Callout",
                category: "Basic Blocks",
                aliases: [],
                keywords: ["highlight", "note", "tip"],
                preview: "Turn text into a callout block.",
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
        for descriptor in builtins {
            register(descriptor)
        }
    }

    /// Register a custom slash command descriptor. Duplicate `id`s are ignored (idempotent).
    static func register(_ descriptor: SlashCommandDescriptor) {
        guard !descriptors.contains(where: { $0.id == descriptor.id }) else { return }
        descriptors.append(descriptor)
    }

    static func editCommands(for match: SlashCommitMatch, blockID: String, blockType: BlockType? = nil) -> [EditCommand]? {
        registerBuiltins()
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

    static func catalogItems() -> [SlashCommandCatalogItem] {
        registerBuiltins()
        return descriptors.map(\.catalogItem)
    }

    static func resolveCatalogCommand(
        catalogID: String,
        queryTokenRange: MiranNotesCore.TextRange,
        blockID: String,
        blockType: BlockType? = nil
    ) -> [EditCommand]? {
        registerBuiltins()
        guard let descriptor = descriptors.first(where: { $0.id == catalogID }) else { return nil }
        guard descriptor.accepts(match: SlashCommitMatch(
            lineStartUTF16: queryTokenRange.start,
            commitUTF16Index: queryTokenRange.end,
            commitCharacter: .newline,
            tokenWithoutSlash: catalogID
        ), blockType: blockType) else {
            return nil
        }
        return descriptor.produce(catalogID, queryTokenRange, blockID)
    }

    private static let defaultCommitPolicy: Set<SlashCommitMatch.CommitCharacter> = [.space, .newline]
}
