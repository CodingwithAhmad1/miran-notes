import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreOnByDefault() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.reopenLastVaultAtLaunch)
        XCTAssertTrue(settings.wikiLinkNavigationEnabled)
        XCTAssertTrue(settings.wikiLinkAutocompleteEnabled)
    }

    func testChangesRoundTripThroughUserDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.reopenLastVaultAtLaunch = false
        settings.wikiLinkNavigationEnabled = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.reopenLastVaultAtLaunch)
        XCTAssertFalse(reloaded.wikiLinkNavigationEnabled)
        XCTAssertTrue(reloaded.wikiLinkAutocompleteEnabled)
    }

    func testReopenPreferenceReadForBootstrap() {
        XCTAssertTrue(AppSettings.reopenLastVaultAtLaunchPreference(defaults: defaults))
        defaults.set(false, forKey: AppSettingsKey.reopenLastVaultAtLaunch)
        XCTAssertFalse(AppSettings.reopenLastVaultAtLaunchPreference(defaults: defaults))
    }
}
