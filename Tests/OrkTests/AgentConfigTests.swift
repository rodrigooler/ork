import XCTest
@testable import Ork

final class AgentConfigTests: XCTestCase {
    func testParsesMinimalAndFullEntries() {
        let json = """
        [
          {"slug": "aider", "name": "Aider", "command": "aider"},
          {"slug": "goose", "name": "Goose", "command": "goose session",
           "symbol": "bird", "tint": "#7FA3C4", "resumeCommand": "goose session -r"}
        ]
        """
        let agents = AgentConfig.parse(Data(json.utf8))
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(agents[0].symbol, "terminal")
        XCTAssertEqual(agents[0].tintHex, 0xC7A566)
        XCTAssertNil(agents[0].resumeCommand)
        XCTAssertEqual(agents[1].tintHex, 0x7FA3C4)
        XCTAssertEqual(agents[1].resumeCommand, "goose session -r")
    }

    func testParseHexAcceptsCommonSpellings() {
        XCTAssertEqual(AgentConfig.parseHex("#F96B2F"), 0xF96B2F)
        XCTAssertEqual(AgentConfig.parseHex("f96b2f"), 0xF96B2F)
        XCTAssertEqual(AgentConfig.parseHex("0xF96B2F"), 0xF96B2F)
        XCTAssertNil(AgentConfig.parseHex("#FFF"))
        XCTAssertNil(AgentConfig.parseHex(nil))
    }

    func testMalformedFileYieldsNoAgents() {
        XCTAssertTrue(AgentConfig.parse(Data("not json".utf8)).isEmpty)
    }

    func testCustomSlugOverridesBuiltin() {
        let json = """
        [{"slug": "claude", "name": "Claude Custom", "command": "claude --dangerously-skip-permissions"}]
        """
        let custom = AgentConfig.parse(Data(json.utf8))
        let customSlugs = Set(custom.map(\.slug))
        let merged = AgentProfile.builtin.filter { !customSlugs.contains($0.slug) } + custom
        XCTAssertEqual(merged.filter { $0.slug == "claude" }.count, 1)
        XCTAssertEqual(merged.first { $0.slug == "claude" }?.name, "Claude Custom")
    }
}
