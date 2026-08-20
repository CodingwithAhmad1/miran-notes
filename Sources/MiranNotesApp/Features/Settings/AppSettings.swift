import Foundation
import Observation

/// UserDefaults keys for app preferences. Shared with nonisolated bootstrap paths (`VaultWorkspaceAccess`).
enum AppSettingsKey {
    static let reopenLastVaultAtLaunch = "settings.reopenLastVaultAtLaunch"
    static let wikiLinkNavigationEnabled = "settings.wikiLinkNavigationEnabled"
    static let wikiLinkAutocompleteEnabled = "settings.wikiLinkAutocompleteEnabled"
    static let editorBodyPointSize = "settings.editorBodyPointSize"
    static let autoRollOverTasks = "settings.autoRollOverTasks"
}

/// App-wide user preferences, UserDefaults-backed. The App owns ``shared`` and injects it into views
/// via `.environment`; new feature toggles belong here rather than as loose `UserDefaults` reads.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    /// Restore the last vault from its security-scoped bookmark at launch (skip the picker).
    var reopenLastVaultAtLaunch: Bool {
        didSet { defaults.set(reopenLastVaultAtLaunch, forKey: AppSettingsKey.reopenLastVaultAtLaunch) }
    }

    /// Style wiki links and allow click-to-follow in the editor.
    var wikiLinkNavigationEnabled: Bool {
        didSet { defaults.set(wikiLinkNavigationEnabled, forKey: AppSettingsKey.wikiLinkNavigationEnabled) }
    }

    /// Show the `[[` note-autocomplete popover while typing.
    var wikiLinkAutocompleteEnabled: Bool {
        didSet { defaults.set(wikiLinkAutocompleteEnabled, forKey: AppSettingsKey.wikiLinkAutocompleteEnabled) }
    }

    /// Editor body text size in points (headings scale proportionally). Range 12–20.
    var editorBodyPointSize: Double {
        didSet { defaults.set(editorBodyPointSize, forKey: AppSettingsKey.editorBodyPointSize) }
    }

    /// Copy unfinished tasks forward automatically when the Today's Tasks page lands on a new, empty day.
    var autoRollOverTasks: Bool {
        didSet { defaults.set(autoRollOverTasks, forKey: AppSettingsKey.autoRollOverTasks) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.reopenLastVaultAtLaunch = Self.bool(defaults, AppSettingsKey.reopenLastVaultAtLaunch, defaultValue: true)
        self.wikiLinkNavigationEnabled = Self.bool(defaults, AppSettingsKey.wikiLinkNavigationEnabled, defaultValue: true)
        self.wikiLinkAutocompleteEnabled = Self.bool(defaults, AppSettingsKey.wikiLinkAutocompleteEnabled, defaultValue: true)
        let storedSize = defaults.object(forKey: AppSettingsKey.editorBodyPointSize) as? Double
        self.editorBodyPointSize = min(max(storedSize ?? 15, 12), 20)
        self.autoRollOverTasks = Self.bool(defaults, AppSettingsKey.autoRollOverTasks, defaultValue: false)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    /// Preference read for nonisolated launch paths (`VaultWorkspaceAccess.bootstrap` runs before any UI exists).
    nonisolated static func reopenLastVaultAtLaunchPreference(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppSettingsKey.reopenLastVaultAtLaunch) == nil
            ? true
            : defaults.bool(forKey: AppSettingsKey.reopenLastVaultAtLaunch)
    }
}
