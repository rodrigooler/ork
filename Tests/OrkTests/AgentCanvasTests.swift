import XCTest
@testable import Ork

final class AgentCanvasTests: XCTestCase {
    func testTreeLayoutCentersTheRootAndWrapsRows() {
        let card = CanvasLayout.cardSize
        let result = CanvasLayout.layout(count: 5, hasRoot: true)
        XCTAssertEqual(result.positions.count, 5)
        // Root centered over the widest row.
        XCTAssertEqual(result.positions[0].x, result.size.width / 2, accuracy: 0.001)
        XCTAssertEqual(result.positions[0].y, card.height / 2, accuracy: 0.001)
        // Four members wrap into rows of three: 3 on the first, 1 on the second.
        let firstRowY = result.positions[1].y
        XCTAssertEqual(result.positions.filter { $0.y == firstRowY }.count, 3)
        XCTAssertGreaterThan(result.positions[4].y, firstRowY)
        // No two cards share a center.
        XCTAssertEqual(Set(result.positions.map { "\($0.x),\($0.y)" }).count, 5)
    }

    func testFlatLayoutHasNoRootSlot() {
        let result = CanvasLayout.layout(count: 3, hasRoot: false)
        XCTAssertEqual(result.positions.count, 3)
        // All three sit on one row.
        XCTAssertEqual(Set(result.positions.map(\.y)).count, 1)
        XCTAssertEqual(CanvasLayout.layout(count: 0, hasRoot: false).positions.count, 0)
    }
}
