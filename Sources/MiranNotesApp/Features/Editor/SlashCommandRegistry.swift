import Foundation
import MiranNotesCore

/// Built-in slash commands (order = longest-prefix / first match for overlapping ids).
enum SlashCommandRegistry {
    static func editCommands(for match: SlashCommitMatch, blockID: String) -> [EditCommand]? {
        let tokenRange = MiranNotesCore.TextRange(
            start: match.lineStartUTF16,
            length: match.commitUTF16Index - match.lineStartUTF16
        )
        let token = match.tokenWithoutSlash

        if SlashHeading.matches(token) {
            return SlashHeading.commands(tokenWithoutSlash: token, tokenRange: tokenRange, blockID: blockID)
        }
        if SlashParagraph.matches(token) {
            return SlashParagraph.commands(tokenRange: tokenRange, blockID: blockID)
        }
        if SlashCode.matches(token) {
            return SlashCode.commands(tokenRange: tokenRange, blockID: blockID)
        }
        if SlashListItem.matches(token) {
            return SlashListItem.commands(tokenRange: tokenRange, blockID: blockID)
        }
        if SlashDivider.matches(token) {
            return SlashDivider.commands(tokenRange: tokenRange, blockID: blockID)
        }
        if SlashCallout.matches(token) {
            return SlashCallout.commands(tokenRange: tokenRange, blockID: blockID)
        }
        return nil
    }
}

private enum SlashHeading {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "h1" || tokenWithoutSlash == "h2" || tokenWithoutSlash == "h3"
    }

    static func commands(tokenWithoutSlash: String, tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        let level: Int
        switch tokenWithoutSlash {
        case "h1": level = 1
        case "h2": level = 2
        case "h3": level = 3
        default: return []
        }
        return [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .heading, headingLevel: level)
        ]
    }
}

private enum SlashParagraph {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "p"
    }

    static func commands(tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .paragraph, headingLevel: nil)
        ]
    }
}

private enum SlashCode {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "code"
    }

    static func commands(tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .code, headingLevel: nil)
        ]
    }
}

private enum SlashListItem {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "list"
    }

    static func commands(tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .listItem, headingLevel: nil)
        ]
    }
}

private enum SlashDivider {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "divider"
    }

    static func commands(tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .divider, headingLevel: nil)
        ]
    }
}

private enum SlashCallout {
    static func matches(_ tokenWithoutSlash: String) -> Bool {
        tokenWithoutSlash == "callout"
    }

    static func commands(tokenRange: MiranNotesCore.TextRange, blockID: String) -> [EditCommand] {
        [
            .replaceText(range: tokenRange, replacement: ""),
            .changeBlockType(blockID: blockID, type: .callout, headingLevel: nil)
        ]
    }
}
