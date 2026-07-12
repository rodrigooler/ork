import XCTest
@testable import OrkMCPCore

final class MCPServerTests: XCTestCase {
    private var root: URL!
    private var teamDir: URL!
    private var server: MCPServer!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ork-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        teamDir = root.appendingPathComponent("team", isDirectory: true)
        try FileManager.default.createDirectory(at: teamDir.appendingPathComponent("outbox"), withIntermediateDirectories: true)
        let bridge = ["teamDir": teamDir.path, "member": "Rodrigo"]
        try JSONSerialization.data(withJSONObject: bridge)
            .write(to: root.appendingPathComponent("abc.json"))
        server = MCPServer(sessionID: "abc", bridgeDir: root, version: "test")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func call(_ tool: String, _ args: [String: Any] = [:]) -> (text: String, isError: Bool) {
        let response = server.handle([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": tool, "arguments": args],
        ])
        let result = response?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return (content?.first?["text"] as? String ?? "", result?["isError"] as? Bool ?? false)
    }

    func testLifecycleAndToolsList() {
        let initialize = server.handle([
            "jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18"],
        ])
        let initResult = initialize?["result"] as? [String: Any]
        XCTAssertEqual(initResult?["protocolVersion"] as? String, "2025-06-18")
        // Notifications get no response.
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        let list = server.handle(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let tools = (list?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.compactMap { $0["name"] as? String }.sorted(),
                       ["team_board", "team_members", "team_send"])
        // Unknown methods error instead of hanging the client.
        let unknown = server.handle(["jsonrpc": "2.0", "id": 2, "method": "resources/list"])
        XCTAssertNotNil(unknown?["error"])
    }

    func testTeamSendWritesTheOutboxContract() throws {
        let reply = call("team_send", ["recipient": "codex-9f9f", "message": "claim 3"])
        XCTAssertFalse(reply.isError)
        let outbox = teamDir.appendingPathComponent("outbox")
        let files = try FileManager.default.contentsOfDirectory(atPath: outbox.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasPrefix("Rodrigo__codex-9f9f__"))
        XCTAssertTrue(files[0].hasSuffix(".md"))
        let content = try String(contentsOf: outbox.appendingPathComponent(files[0]), encoding: .utf8)
        XCTAssertEqual(content, "claim 3")
        // Malformed recipients never reach the filesystem.
        XCTAssertTrue(call("team_send", ["recipient": "a__b", "message": "x"]).isError)
        XCTAssertTrue(call("team_send", ["recipient": "", "message": "x"]).isError)
    }

    func testBoardAndMembersReadThroughTheBridge() throws {
        try "# Team Board".write(to: teamDir.appendingPathComponent("board.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(call("team_board").text, "# Team Board")
        XCTAssertEqual(call("team_members").text, "No roster yet.")
    }

    func testMissingBridgeMeansNotOnATeam() {
        let lonely = MCPServer(sessionID: "ghost", bridgeDir: root, version: "test")
        let response = lonely.handle([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "team_send", "arguments": ["recipient": "all", "message": "hi"]],
        ])
        let result = response?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true)
    }
}
