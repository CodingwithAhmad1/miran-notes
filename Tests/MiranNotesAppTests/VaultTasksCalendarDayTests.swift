import XCTest

@testable import MiranNotesApp

final class VaultTasksCalendarDayTests: XCTestCase {
    func testDisplayShortYYMMDDUsesFixedFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = VaultTasksCalendarDay(validatedStorageKey: "2026-04-17")
        XCTAssertEqual(day.displayShortYYMMDD(calendar: cal), "26/04/17")
    }

    func testStorageKeyOrdersLexicographicallyByDate() {
        let a = VaultTasksCalendarDay(validatedStorageKey: "2026-04-09")
        let b = VaultTasksCalendarDay(validatedStorageKey: "2026-04-10")
        XCTAssertTrue(a < b)
    }
}
