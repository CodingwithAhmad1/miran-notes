import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class VaultDirectoryWatcherTests: XCTestCase {
    /// Many rapid FSEvent callbacks should coalesce into a single debounced `onEvent`.
    func testBurstCoalescesToSingleOnEvent() async {
        let exp = expectation(description: "onEvent")
        exp.expectedFulfillmentCount = 1
        var callCount = 0
        let watcher = VaultDirectoryWatcher(debounceMillisecondsForTests: 35) {
            callCount += 1
            exp.fulfill()
        }
        defer { watcher.cancel() }

        for _ in 0..<25 {
            watcher.handleFSEvent()
        }

        await fulfillment(of: [exp], timeout: 3.0)
        XCTAssertEqual(callCount, 1, "Burst should yield exactly one handler invocation")
    }

    /// After the debounce window passes, a new burst should schedule another `onEvent`.
    func testSecondBurstAfterQuietFiresAgain() async {
        let exp1 = expectation(description: "first onEvent")
        let exp2 = expectation(description: "second onEvent")
        var callCount = 0
        let watcher = VaultDirectoryWatcher(debounceMillisecondsForTests: 30) {
            callCount += 1
            if callCount == 1 { exp1.fulfill() }
            if callCount == 2 { exp2.fulfill() }
        }
        defer { watcher.cancel() }

        for _ in 0..<12 {
            watcher.handleFSEvent()
        }
        await fulfillment(of: [exp1], timeout: 2.0)

        try? await Task.sleep(for: .milliseconds(200))

        for _ in 0..<12 {
            watcher.handleFSEvent()
        }
        await fulfillment(of: [exp2], timeout: 2.0)
        XCTAssertEqual(callCount, 2)
    }
}
