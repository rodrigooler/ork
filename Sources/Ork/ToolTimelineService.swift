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
}
