import Foundation

/// High-level editor backend selected at launch (and eventually from Settings).
enum EditorKind: String, Codable, Equatable, Sendable {
    /// Block-aware `NSTextView` pipeline (layout controller, slash menu, block chrome).
    case blockNative
    /// Plain note body as markdown source: minimal structure UI, mostly `.replaceText` edits.
    case plainMarkdownSource
}

/// Fine-grained feature flags; interpreted together with ``EditorKind`` via ``EditorActivationProfile/effectiveModules``.
struct EditorModuleFlags: Codable, Equatable, Sendable {
    var blockChrome: Bool
    var slashMenu: Bool
    var markdownShortcutDetector: Bool
    /// When false, wiki `[[...]]` tokens are not click-navigable even if presentation styling is on.
    var wikiLinkClickThrough: Bool
    /// When false, newline/tab typing does not run ``DocumentLayoutController`` structural commands.
    var layoutControllerNewlineRules: Bool

    static let blockNativeDefault = EditorModuleFlags(
        blockChrome: true,
        slashMenu: true,
        markdownShortcutDetector: true,
        wikiLinkClickThrough: true,
        layoutControllerNewlineRules: true
    )

    static let plainMarkdownDefault = EditorModuleFlags(
        blockChrome: false,
        slashMenu: false,
        markdownShortcutDetector: false,
        wikiLinkClickThrough: true,
        layoutControllerNewlineRules: false
    )
}

/// Single configuration object for “which editor modules are active.”
struct EditorActivationProfile: Codable, Equatable, Sendable {
    var editorKind: EditorKind
    /// Stored preferences; use ``effectiveModules`` for the flags surfaces should honor.
    var modules: EditorModuleFlags

    /// Default shipping configuration: block editor with all modules on.
    static let shippingDefault = EditorActivationProfile(
        editorKind: .blockNative,
        modules: .blockNativeDefault
    )

    var effectiveModules: EditorModuleFlags {
        switch editorKind {
        case .blockNative:
            return modules
        case .plainMarkdownSource:
            var m = EditorModuleFlags.plainMarkdownDefault
            m.markdownShortcutDetector = modules.markdownShortcutDetector
            m.wikiLinkClickThrough = modules.wikiLinkClickThrough
            return m
        }
    }

    /// Reads `MIRAN_EDITOR_KIND` when present: `markdown`, `plain`, `plainMarkdown`, `plainMarkdownSource` → plain source editor; otherwise block native.
    static func resolvedFromEnvironment() -> EditorActivationProfile {
        resolve(kindRaw: ProcessInfo.processInfo.environment["MIRAN_EDITOR_KIND"])
    }

    static func resolve(kindRaw: String?) -> EditorActivationProfile {
        guard let raw = kindRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .shippingDefault
        }
        switch raw.lowercased() {
        case "markdown", "plain", "plainmarkdown", "plain_markdown", "plainmarkdownsource":
            return EditorActivationProfile(
                editorKind: .plainMarkdownSource,
                modules: .plainMarkdownDefault
            )
        default:
            return .shippingDefault
        }
    }
}
