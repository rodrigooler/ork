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
                       ["ork_configure_member", "ork_disband_member", "ork_project_info", "ork_spawn_member",
                        "team_board", "team_members", "team_send"])
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

    // MARK: - Manager orchestration

    private func promoteToManager() throws {
        let bridge: [String: Any] = ["teamDir": teamDir.path, "member": "manager", "manager": true,
                                     "workspace": "acme", "directory": "/tmp/acme"]
        try JSONSerialization.data(withJSONObject: bridge)
            .write(to: root.appendingPathComponent("abc.json"))
    }

    func testOrchestrationToolsAreManagerOnly() {
        let reply = call("ork_spawn_member", ["name": "ana", "role": "QA"])
        XCTAssertTrue(reply.isError)
        XCTAssertTrue(reply.text.contains("manager only"))
    }

    func testProjectInfoBundlesWorkspaceRosterAndBoard() throws {
        try promoteToManager()
        try "- ana: /tmp/wt".write(to: teamDir.appendingPathComponent("members.md"), atomically: true, encoding: .utf8)
        let reply = call("ork_project_info")
        XCTAssertFalse(reply.isError)
        XCTAssertTrue(reply.text.contains("Workspace: acme"))
        XCTAssertTrue(reply.text.contains("Directory: /tmp/acme"))
        XCTAssertTrue(reply.text.contains("- ana: /tmp/wt"))
    }

    func testMutationTimesOutAsNotApproved() throws {
        try promoteToManager()
        server = MCPServer(sessionID: "abc", bridgeDir: root, version: "test", approvalTimeout: 0.6)
        let reply = call("ork_disband_member", ["name": "ana"])
        XCTAssertFalse(reply.isError)
        XCTAssertTrue(reply.text.contains("not approved"))
        // The stale request is cleaned up so Ork never sees it later.
        let requests = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("requests").path)
        XCTAssertTrue(requests.isEmpty)
    }

    func testApprovedMutationReturnsTheOutcome() throws {
        try promoteToManager()
        server = MCPServer(sessionID: "abc", bridgeDir: root, version: "test", approvalTimeout: 5)
        let requests = root.appendingPathComponent("requests", isDirectory: true)
        // Play Ork: watch for the request file and write the approval.
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: requests.path),
                   let name = files.first(where: { $0.hasSuffix(".json") && !$0.hasSuffix(".response.json") }) {
                    let id = name.replacingOccurrences(of: ".json", with: "")
                    let response = try? JSONSerialization.data(withJSONObject: ["approved": true, "result": "spawned 'ana'"])
                    try? response?.write(to: requests.appendingPathComponent("\(id).response.json"))
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        let reply = call("ork_spawn_member", ["name": "ana", "role": "QA engineer"])
        XCTAssertFalse(reply.isError)
        XCTAssertEqual(reply.text, "spawned 'ana'")
    }
}
