# UI tests (XCUITest)

This directory is reserved for **XCUITest** targets when the project is opened in Xcode with a test host application.

Swift Package Manager’s `swift test` does not run XCUITest; use Xcode’s **Test** action with the app target as host, or add a separate Xcode workspace/project that references the package and declares a UI test bundle. See [docs/testing/ui-tests.md](../docs/testing/ui-tests.md) for setup notes and a minimal smoke checklist.
