import XCTest
import NIOCore
import RediStack
@testable import Ork

final class QueryServiceTests: XCTestCase {
    func testTokenizeHonorsQuotes() {
        XCTAssertEqual(QueryService.tokenize("GET mykey"), ["GET", "mykey"])
        XCTAssertEqual(QueryService.tokenize(#"SET greeting "hello world""#), ["SET", "greeting", "hello world"])
        XCTAssertEqual(QueryService.tokenize("SET k 'a b'"), ["SET", "k", "a b"])
        XCTAssertEqual(QueryService.tokenize("  PING  "), ["PING"])
        XCTAssertEqual(QueryService.tokenize(""), [])
    }

    func testRenderRESPValues() {
        XCTAssertEqual(QueryService.render(.null), "(nil)")
        XCTAssertEqual(QueryService.render(.integer(42)), "(integer) 42")
        XCTAssertEqual(QueryService.render(.simpleString(ByteBuffer(string: "OK"))), "OK")
        XCTAssertEqual(QueryService.render(.bulkString(nil)), "(nil)")
        let array = RESPValue.array([.integer(1), .bulkString(ByteBuffer(string: "two"))])
        XCTAssertEqual(QueryService.render(array), "1) (integer) 1\n2) two")
    }

    func testGridAlignsColumns() {
        var table = QueryService.Table()
        table.columns = ["id", "name"]
        table.rows = [["1", "ada"], ["22", "grace hopper"]]
        let lines = QueryConsole.grid(table)
        XCTAssertEqual(lines[0], "id  name        ")
        XCTAssertEqual(lines[1], "1   ada         ")
        XCTAssertEqual(lines[2], "22  grace hopper")
    }
}
