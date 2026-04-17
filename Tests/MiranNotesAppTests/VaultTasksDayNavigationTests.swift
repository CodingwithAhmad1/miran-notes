import XCTest

@testable import MiranNotesApp

final class VaultTasksDayNavigationTests: XCTestCase {
    func testPreviousNextAdjacent() {
        let a = VaultTasksCalendarDay(validatedStorageKey: "2026-04-08")
        let b = VaultTasksCalendarDay(validatedStorageKey: "2026-04-10")
        let c = VaultTasksCalendarDay(validatedStorageKey: "2026-04-12")
        let sorted = [a, b, c]
        XCTAssertEqual(VaultTasksDayNavigation.previous(before: b, knownSorted: sorted), a)
        XCTAssertEqual(VaultTasksDayNavigation.next(after: b, knownSorted: sorted), c)
        XCTAssertNil(VaultTasksDayNavigation.previous(before: a, knownSorted: sorted))
        XCTAssertNil(VaultTasksDayNavigation.next(after: c, knownSorted: sorted))
    }

    func testPreviousSkipsGap() {
        let a = VaultTasksCalendarDay(validatedStorageKey: "2026-04-08")
        let c = VaultTasksCalendarDay(validatedStorageKey: "2026-04-10")
        let sorted = [a, c]
        XCTAssertEqual(VaultTasksDayNavigation.previous(before: c, knownSorted: sorted), a)
        XCTAssertEqual(VaultTasksDayNavigation.next(after: a, knownSorted: sorted), c)
    }
}
