import Foundation

/// Deterministic rules for whether a directory tree is a valid Miran **flat workspace**
/// (workspace → top-level folders → `.txt` notes). See ``WorkspaceCompatibilityScanner``.
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

    /// Miran persists `NoteMetadata` beside each `.txt` using this suffix.
    static let metadataSidecarSuffix = ".meta.json"

    /// Maximum issues listed in the blocking UI (deterministic cap).
    static let maxIssuesInUI = 5
}
