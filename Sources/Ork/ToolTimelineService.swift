import Foundation

/// One tool call an agent made, read from its CLI transcript.
struct ToolEvent: Equatable {
    let time: Date
    let tool: String
    let detail: String
}

/// Live tool events per session from Claude Code transcripts
/// (~/.claude/projects/<encoded-dir>/*.jsonl). Claude only: the other CLIs
/// have no stable local transcript convention yet.
enum ToolTimelineService {
    /// Claude Code names the transcript folder by replacing every
    /// non-alphanumeric path character with '-'.
    static func encodedProjectDir(_ directory: String) -> String {
        String(directory.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Latest tool events for the session's directory, oldest first.
    /// Reads only the tail of the newest transcript, so polling stays cheap.
    static func recentEvents(directory: String, limit: Int = 10) -> [ToolEvent] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encodedProjectDir(directory))", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        let newest = files.filter { $0.pathExtension == "jsonl" }.max { mtime($0) < mtime($1) }
        guard let newest, let chunk = tail(of: newest, bytes: 262_144) else { return [] }
        return Array(parse(chunk).suffix(limit))
    }

    private static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Last `bytes` of the file, trimmed to whole lines.
    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        guard offset > 0, let firstNewline = text.firstIndex(of: "\n") else { return text }
        return String(text[text.index(after: firstNewline)...])
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    /// Pulls tool_use blocks out of assistant transcript lines.
    static func parse(_ text: String) -> [ToolEvent] {
        var events: [ToolEvent] = []
        for line in text.split(separator: "\n") {
            guard line.contains("\"tool_use\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            let stamp = object["timestamp"] as? String ?? ""
            let time = fractional.date(from: stamp) ?? plain.date(from: stamp) ?? Date()
            for block in content where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                events.append(ToolEvent(time: time, tool: name, detail: detail(from: block["input"])))
            }
        }
        return events
    }

    /// The one input field a human wants to see, tool-agnostic.
    static func detail(from input: Any?) -> String {
        guard let input = input as? [String: Any] else { return "" }
        for key in ["command", "file_path", "pattern", "query", "url", "prompt", "description"] {
            if let value = input[key] as? String, !value.isEmpty {
                return String(value.replacingOccurrences(of: "\n", with: " ").prefix(64))
            }
        }
        return ""
    }

    fileprivate static func newestTranscript(directory: String) -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encodedProjectDir(directory))", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        return files.filter { $0.pathExtension == "jsonl" }.max { mtime($0) < mtime($1) }
    }
}

/// Live snapshot of one claude session, read incrementally from its transcript.
struct SessionTelemetry: Equatable {
    var lastTool: ToolEvent?
    var model: String?
    var outputTokens = 0   // cumulative for the transcript
    var contextTokens = 0  // input side of the newest message ≈ context size
    var lastActivity: Date?
}

/// Reads each transcript once, then only the bytes appended since the last
/// call, so polling stays cheap even on transcripts tens of MB long.
enum SessionTelemetryService {
    private struct FileState {
        var offset: UInt64 = 0
        var telemetry = SessionTelemetry()
        var seenMessageIDs = Set<String>()
    }

    private static var cache: [String: FileState] = [:]
    private static let lock = NSLock()

    static func snapshot(directory: String) -> SessionTelemetry? {
        guard let transcript = ToolTimelineService.newestTranscript(directory: directory) else { return nil }
        return snapshot(transcript: transcript)
    }

    static func snapshot(transcript: URL) -> SessionTelemetry? {
        lock.lock()
        defer { lock.unlock() }
        var state = cache[transcript.path] ?? FileState()
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return cache[transcript.path]?.telemetry }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = FileState() }  // truncated or replaced
        try? handle.seek(toOffset: state.offset)
        if let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) {
            let chunk = String(decoding: data[data.startIndex...lastNewline], as: UTF8.self)
            ingest(chunk, into: &state)
            state.offset += UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        }
        cache[transcript.path] = state
        return state.telemetry
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_read_input_tokens: Int?
                let cache_creation_input_tokens: Int?
            }

            let id: String?
            let model: String?
            let usage: Usage?
        }

        let timestamp: String?
        let message: Message?
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    private static func ingest(_ chunk: String, into state: inout FileState) {
        if let tool = ToolTimelineService.parse(chunk).last {
            state.telemetry.lastTool = tool
        }
        for lineText in chunk.split(separator: "\n") {
            guard lineText.contains("\"timestamp\""),
                  let line = try? JSONDecoder().decode(Line.self, from: Data(lineText.utf8)) else { continue }
            if let stamp = line.timestamp, let date = fractional.date(from: stamp) ?? plain.date(from: stamp) {
                state.telemetry.lastActivity = date
            }
            guard let message = line.message else { continue }
            if let model = message.model { state.telemetry.model = model }
            guard let usage = message.usage else { continue }
            state.telemetry.contextTokens = (usage.input_tokens ?? 0)
                + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0)
            // Streamed entries repeat a message id; count output once, like UsageService.
            if let id = message.id {
                if state.seenMessageIDs.contains(id) { continue }
                state.seenMessageIDs.insert(id)
            }
            state.telemetry.outputTokens += usage.output_tokens ?? 0
        }
    }
}
