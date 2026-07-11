import XCTest
@testable import Ork

final class AgentCanvasTests: XCTestCase {
    func testOrbitPositionsAreEvenlySpacedOnTheRing() {
        let radius: CGFloat = 100
        let count = 4
        let points = (0..<count).map {
            AgentCanvasScene.orbitPosition(index: $0, count: count, radius: radius)
        }
        for point in points {
            XCTAssertEqual(hypot(point.x, point.y), radius, accuracy: 0.001)
        }
        // First slot sits at the top; the four points are distinct.
        XCTAssertEqual(points[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(points[0].y, radius, accuracy: 0.001)
        XCTAssertEqual(Set(points.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }).count, count)
        XCTAssertEqual(AgentCanvasScene.orbitPosition(index: 0, count: 0, radius: radius), .zero)
    }
}
