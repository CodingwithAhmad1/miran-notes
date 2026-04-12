# UI and snapshot tests

The Swift Package (`Package.swift`) builds the macOS app executable and unit tests. **XCUITest** and App Store–style UI tests typically require an **Xcode project or workspace** that embeds the SPM target and exposes a **UI Test Bundle** target with a test host.

## Recommended setup

1. Create an Xcode workspace that includes this package.
2. Add a **UI Testing Bundle** target with the MiranNotes app as the **Target Application**.
3. Implement smoke flows: launch, create note, type `/`, dismiss slash menu, sidebar search.

## Snapshot testing

For editor chrome and SwiftUI sidebars, consider **swift-snapshot-testing** or Xcode **Accessory** screenshot tests against a small set of stable view controllers. Keep golden files to **4–6** scenarios to limit maintenance.

## Placeholder

Until a workspace exists, critical UI paths remain covered by manual QA (`docs/plans/editor-interaction-scenarios.md`) and `MiranNotesAppTests` integration tests around `AppModel`.

The repository root [UITests/README.md](../../UITests/README.md) documents the intended folder for an Xcode-hosted UI test bundle once you add a workspace.
