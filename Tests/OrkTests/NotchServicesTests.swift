import XCTest
@testable import Ork

final class PromptWatchTests: XCTestCase {
    private let permissionPrompt = [
        "╭──────────────────────────────────────────╮",
        "│ Bash command                             │",
        "│                                          │",
        "│   rm -rf node_modules                    │",
        "│                                          │",
        "│ Do you want to proceed?                  │",
        "│ ❯ 1. Yes                                 │",
        "│   2. Yes, and don't ask again for rm     │",
        "│      commands in /Users/me/www/proj      │",
        "│   3. No, and tell Claude what to do      │",
        "│      differently (esc)                   │",
        "╰──────────────────────────────────────────╯",
    ]

    func testDetectsPermissionPrompt() {
        let prompt = PromptWatchService.detect(lines: permissionPrompt)
        XCTAssertEqual(prompt?.title, "Do you want to proceed?")
        XCTAssertEqual(prompt?.options.count, 3)
        XCTAssertEqual(prompt?.options.first?.key, "1")
        XCTAssertEqual(prompt?.options.first?.label, "Yes")
    }

    func testDetectsPlanPromptWithoutFrame() {
        let lines = [
            "Here is the plan summary.",
            "",
            "Would you like to proceed?",
            "❯ 1. Yes, and auto-accept edits",
            "  2. Yes, and manually approve edits",
            "  3. No, keep planning",
        ]
        let prompt = PromptWatchService.detect(lines: lines)
        XCTAssertEqual(prompt?.title, "Would you like to proceed?")
        XCTAssertEqual(prompt?.options.count, 3)
    }

    func testNumberedListInOutputDoesNotMatch() {
        // No ❯ selector anywhere: ordinary markdown output, not a prompt.
        let lines = [
            "Top findings?",
            "1. The cache is stale",
            "2. The lock is held too long",
        ]
        XCTAssertNil(PromptWatchService.detect(lines: lines))
    }

    func testSelectorWithoutQuestionTitleDoesNotMatch() {
        let lines = [
            "Installing dependencies",
            "❯ 1. package-a",
            "  2. package-b",
        ]
        XCTAssertNil(PromptWatchService.detect(lines: lines))
    }

    func testBrokenNumberingRestartsTheBlock() {
        let lines = [
            "Do you want to proceed?",
            "❯ 1. Yes",
            "  3. No",
        ]
        XCTAssertNil(PromptWatchService.detect(lines: lines))
    }

    func testLargeGapAfterOptionsDropsTheBlock() {
        var lines = permissionPrompt
        lines.append(contentsOf: ["", "", "output line", "another", "more output", "keeps flowing"])
        XCTAssertNil(PromptWatchService.detect(lines: lines))
    }
}

final class SessionTelemetryTests: XCTestCase {
    private func transcriptLine(id: String, model: String = "claude-fable-5",
                                output: Int, contextRead: Int, timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":10,"output_tokens":\(output),"cache_read_input_tokens":\(contextRead),"cache_creation_input_tokens":5}}}
        """
    }

    func testAccumulatesIncrementally() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = transcriptLine(id: "m1", output: 100, contextRead: 1_000, timestamp: "2026-07-12T10:00:00Z")
        try (first + "\n").write(to: url, atomically: true, encoding: .utf8)
        var snapshot = SessionTelemetryService.snapshot(transcript: url)
        XCTAssertEqual(snapshot?.outputTokens, 100)
        XCTAssertEqual(snapshot?.contextTokens, 1_015)
        XCTAssertEqual(snapshot?.model, "claude-fable-5")

        let second = transcriptLine(id: "m2", output: 40, contextRead: 2_000, timestamp: "2026-07-12T10:05:00Z")
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((second + "\n").utf8))
        try handle.close()

        snapshot = SessionTelemetryService.snapshot(transcript: url)
        XCTAssertEqual(snapshot?.outputTokens, 140)
        XCTAssertEqual(snapshot?.contextTokens, 2_015)
    }

    func testRepeatedMessageIDCountsOutputOnce() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let line = transcriptLine(id: "m1", output: 100, contextRead: 0, timestamp: "2026-07-12T10:00:00Z")
        try (line + "\n" + line + "\n").write(to: url, atomically: true, encoding: .utf8)
        let snapshot = SessionTelemetryService.snapshot(transcript: url)
        XCTAssertEqual(snapshot?.outputTokens, 100)
    }
}

final class LimitsServiceTests: XCTestCase {
    func testParsesCodexRateLimits() {
        let line = """
        {"timestamp":"2026-07-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_tokens":1234},"rate_limits":{"limit_id":"codex","primary":{"used_percent":34.5,"window_minutes":300,"resets_at":1772331624},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1772931624}}}}
        """
        let limits = LimitsService.parseCodexLine(line)
        XCTAssertEqual(limits?.primary?.usedPercent, 34.5)
        XCTAssertEqual(limits?.primary?.windowMinutes, 300)
        XCTAssertEqual(limits?.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(limits?.primary?.resetsAt, Date(timeIntervalSince1970: 1_772_331_624))
    }

    func testJunkLineParsesToNil() {
        XCTAssertNil(LimitsService.parseCodexLine("{\"rate_limits\": \"soon\"}"))
        XCTAssertNil(LimitsService.parseCodexLine("not json"))
    }

    func testCostUsesPrefixPricingAndCacheRates() {
        // 1M input at $3 + 1M output at $15 + 1M cache read at $0.3 + 1M cache write at $3.75
        let cost = UsageService.costUSD(model: "claude-sonnet-5", input: 1_000_000, output: 1_000_000,
                                        cacheRead: 1_000_000, cacheWrite: 1_000_000)
        XCTAssertEqual(cost ?? 0, 3 + 15 + 0.3 + 3.75, accuracy: 0.001)
        XCTAssertNil(UsageService.costUSD(model: "claude-fable-5", input: 1, output: 1, cacheRead: 0, cacheWrite: 0))
        XCTAssertNil(UsageService.costUSD(model: nil, input: 1, output: 1, cacheRead: 0, cacheWrite: 0))
    }
}
