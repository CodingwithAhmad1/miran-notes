import Foundation

/// Controls whether wiki-style note links (`NoteLink` / `[[...]]`) are **surfaced in the macOS UI**.
///
/// **Not deleted:** `NoteLink`, `EditCommand.insertWikiLink`, the link graph, and on-disk metadata remain fully
/// implemented so vaults keep working and the feature can be re-enabled later.
/// When this is `false`, the editor does not highlight link spans or handle click-to-navigate; existing link data is unchanged.
enum WikiLinkPresentationPolicy {
    static let isFrontendEnabled = false
}
