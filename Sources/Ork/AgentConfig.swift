import Foundation

/// Custom agents defined by hand in Application Support/Ork/agents.json.
/// Minimal entry: slug, name, command. Optional: symbol (SF Symbol name),
/// tint ("#RRGGBB") and resumeCommand.
enum AgentConfig {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agents.json")
    }()

    private struct Entry: Decodable {
        let slug: String
        let name: String
        let command: String
        var symbol: String?
        var tint: String?
        var resumeCommand: String?
    }

    static func load() -> [AgentProfile] {
        guard let data = try? Data(contentsOf: url) else {
            try? Data("[]".utf8).write(to: url)
            return []
        }
        return parse(data)
    }

    static func parse(_ data: Data) -> [AgentProfile] {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map { entry in
            AgentProfile(
                slug: entry.slug,
                name: entry.name,
                command: entry.command,
                symbol: entry.symbol ?? "terminal",
                tintHex: parseHex(entry.tint) ?? 0xC7A566,
                configResume: entry.resumeCommand
            )
        }
    }

    static func parseHex(_ raw: String?) -> UInt32? {
        guard let raw else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "0x", with: "")
        guard cleaned.count == 6 else { return nil }
        return UInt32(cleaned, radix: 16)
    }
}
