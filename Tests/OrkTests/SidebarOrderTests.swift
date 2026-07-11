import XCTest
@testable import Ork

final class SidebarOrderTests: XCTestCase {
    private struct Item: Identifiable, Equatable {
        let id: Int
    }

    func testReorderedDropTakesTheTargetsPlace() {
        let items = [1, 2, 3, 4].map(Item.init)
        // Moving down lands after the target.
        XCTAssertEqual(AppStore.reordered(items, moving: 1, onto: 3).map(\.id), [2, 3, 1, 4])
        // Moving up lands before the target.
        XCTAssertEqual(AppStore.reordered(items, moving: 4, onto: 2).map(\.id), [1, 4, 2, 3])
        // Self-drop and unknown ids are no-ops.
        XCTAssertEqual(AppStore.reordered(items, moving: 2, onto: 2).map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(AppStore.reordered(items, moving: 9, onto: 2).map(\.id), [1, 2, 3, 4])
        // Adjacent swap works both ways.
        XCTAssertEqual(AppStore.reordered(items, moving: 1, onto: 2).map(\.id), [2, 1, 3, 4])
        XCTAssertEqual(AppStore.reordered(items, moving: 2, onto: 1).map(\.id), [2, 1, 3, 4])
    }
}
