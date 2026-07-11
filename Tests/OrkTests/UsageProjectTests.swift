import XCTest
@testable import Ork

final class UsageProjectTests: XCTestCase {
    func testProjectDisplayNameStripsTheHomePrefix() {
        XCTAssertEqual(UsageService.projectDisplayName("-Users-me-www-ork", home: "/Users/me"), "www-ork")
        XCTAssertEqual(UsageService.projectDisplayName("-Users-me-app", home: "/Users/me"), "app")
        // Folders outside home keep the raw encoded name.
        XCTAssertEqual(UsageService.projectDisplayName("-opt-work", home: "/Users/me"), "-opt-work")
    }
}
