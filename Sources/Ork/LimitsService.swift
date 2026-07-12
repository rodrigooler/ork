import Foundation

/// One rate-limit window as the agent's CLI reports it.
struct RateWindow: Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?
}

struct CodexLimits: Equatable {
    var primary: RateWindow?
    var secondary: RateWindow?
}

/// Real rate-limit numbers from Codex session logs
/// (~/.codex/sessions/**/*.jsonl, token_count events carry rate_limits).
/// Claude has no persisted equivalent; its side comes from UsageService.
enum LimitsService {
    static func codex() -> CodexLimits? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        var newest: (url: URL, mtime: Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if newest == nil || mtime > newest!.mtime { newest = (url, mtime) }
        }
        guard let newest, let chunk = tail(of: newest.url, bytes: 65_536) else { return nil }
        for line in chunk.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            if let limits = parseCodexLine(String(line)) { return limits }
        }
        return nil
    }

    static func parseCodexLine(_ line: String) -> CodexLimits? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        guard let rateLimits = find(key: "rate_limits", in: object) as? [String: Any] else { return nil }
        let limits = CodexLimits(
            primary: window(rateLimits["primary"]),
            secondary: window(rateLimits["secondary"])
        )
        return limits.primary == nil && limits.secondary == nil ? nil : limits
    }

    /// rate_limits nests differently across codex versions; search for the key.
    private static func find(key: String, in object: Any) -> Any? {
        guard let dict = object as? [String: Any] else { return nil }
        if let value = dict[key] { return value }
        for value in dict.values {
            if let found = find(key: key, in: value) { return found }
        }
        return nil
    }

    private static func window(_ value: Any?) -> RateWindow? {
        guard let dict = value as? [String: Any],
              let used = dict["used_percent"] as? Double else { return nil }
        let resets = (dict["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return RateWindow(
            usedPercent: used,
            windowMinutes: dict["window_minutes"] as? Int ?? 0,
            resetsAt: resets
        )
    }

    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
