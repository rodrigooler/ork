import XCTest
@testable import Ork

final class ConsoleHistoryTests: XCTestCase {
    func testPushedDedupsAndCaps() {
        var history = ConsoleHistory.pushed("select 1", onto: [])
        history = ConsoleHistory.pushed("select 2", onto: history)
        XCTAssertEqual(history, ["select 2", "select 1"])
        // Recalling an old query moves it to the top, no duplicate.
        history = ConsoleHistory.pushed("select 1", onto: history)
        XCTAssertEqual(history, ["select 1", "select 2"])
        // Cap holds.
        let many = (0..<60).map { "q\($0)" }
        let capped = many.reduce([]) { ConsoleHistory.pushed($1, onto: $0) }
        XCTAssertEqual(capped.count, ConsoleHistory.cap)
        XCTAssertEqual(capped.first, "q59")
    }
}
