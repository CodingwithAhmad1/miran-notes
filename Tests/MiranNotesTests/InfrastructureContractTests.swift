import XCTest

@testable import MiranNotesCore

final class InfrastructureContractTests: XCTestCase {
    func testTableColumnTypeValidation() {
        XCTAssertTrue(TableColumnType.number.accepts("42.5"))
        XCTAssertFalse(TableColumnType.number.accepts("abc"))
        XCTAssertTrue(TableColumnType.boolean.accepts("true"))
        XCTAssertFalse(TableColumnType.boolean.accepts("maybe"))
    }

    func testExtensionCompatibilityRequiresCapabilitiesAndVersion() {
        let descriptor = ExtensionDescriptor(
            id: "ext.sample",
            version: 1,
            capabilities: [.commandInterception, .commandProduction]
        )
        XCTAssertTrue(
            ExtensionCompatibility.supports(
                descriptor: descriptor,
                requiredVersion: .v1,
                requiredCapabilities: [.commandInterception]
            )
        )
        XCTAssertFalse(
            ExtensionCompatibility.supports(
                descriptor: descriptor,
                requiredVersion: .v1,
                requiredCapabilities: [.syncHooks]
            )
        )
    }
}
