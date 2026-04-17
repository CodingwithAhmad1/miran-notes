import Foundation

/// Deterministic rules for whether a directory tree is a valid Miran **flat workspace**
/// (vault root → top-level topic folders → `.txt` or `.md` note bodies inside each folder, one format per folder).
///
/// Symlinks and nested directories inside topic folders fail the scan; see ``WorkspaceCompatibilityScanner``.
/// For manifest-relative paths and indexes, see `docs/adr/0003-folders-paths-and-manifest-v2.md`.
enum WorkspaceCompatibilityPolicy {
    /// App-internal directories at the vault root (not shown as folder pages).
    static let appRootDirectoryNames: Set<String> = [".miran", "_aux"]

    /// Noise files allowed at vault root or inside topic folders.
    static let ignoredNoiseFileNames: Set<String> = [
        ".DS_Store",
        "Thumbs.db",
        ".localized",
    ]

    /// Optional config file at vault root (future use).
    static let allowedOptionalRootFileNames: Set<String> = [".miran-workspace.json"]

    static let noteFileExtension = "txt"

    /// Allowed note body extensions. Each topic folder (and the vault root note tray) must use only one of these across all notes in that folder.
    static let noteBodyExtensions: Set<String> = ["txt", "md"]

    /// Miran persists `NoteMetadata` beside each note body using this suffix.
    static let metadataSidecarSuffix = ".meta.json"

    /// Maximum issues listed in the blocking UI (deterministic cap).
    static let maxIssuesInUI = 5
}
