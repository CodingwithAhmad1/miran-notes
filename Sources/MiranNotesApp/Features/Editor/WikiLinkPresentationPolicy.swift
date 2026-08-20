import Foundation

/// Controls whether wiki-style note links (`NoteLink` / `[[...]]`) are **surfaced in the macOS UI**.
///
/// Backed by the same UserDefaults keys as ``AppSettings`` so the Settings toggles apply everywhere,
/// including nonisolated styling paths (`EditorVisualStyle`). Link data on disk is unaffected either way.
enum WikiLinkPresentationPolicy {
    /// Style link ranges and route clicks to navigation.
    static var isFrontendEnabled: Bool {
        boolPreference(AppSettingsKey.wikiLinkNavigationEnabled, defaultValue: true)
    }

    /// Show the `[[` note-autocomplete popover while typing.
    static var isAutocompleteEnabled: Bool {
        boolPreference(AppSettingsKey.wikiLinkAutocompleteEnabled, defaultValue: true)
    }

    private static func boolPreference(_ key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}
