import SwiftUI

struct AgentProfile: Identifiable, Codable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let command: String
    let symbol: String
    let tintHex: UInt32
    /// Resume command from agents.json; optional so old state.json still decodes.
    var configResume: String?

    var tint: Color { Color(hex: tintHex) }

    /// Reattaches the CLI to its last conversation in the session directory,
    /// falling back to a fresh start when there is nothing to continue.
    /// Only flags verified against the installed CLIs; others relaunch plain.
    var resumeCommand: String? {
        if let configResume { return configResume }
        switch slug {
        case "claude": return "(claude --continue || claude)"
        case "opencode": return "(opencode --continue || opencode)"
        default: return nil
        }
    }

    static let builtin: [AgentProfile] = [
        AgentProfile(slug: "claude", name: "Claude Code", command: "claude", symbol: "sparkles", tintHex: 0xD97757),
        AgentProfile(slug: "codex", name: "Codex", command: "codex", symbol: "cpu", tintHex: 0x97B380),
        AgentProfile(slug: "opencode", name: "OpenCode", command: "opencode", symbol: "chevron.left.forwardslash.chevron.right", tintHex: 0x7FA3C4),
        AgentProfile(slug: "gemini", name: "Gemini CLI", command: "gemini", symbol: "diamond", tintHex: 0xA08FC9),
        AgentProfile(slug: "shell", name: "Shell", command: "exec zsh", symbol: "terminal", tintHex: 0xC7A566),
    ]

    private(set) static var custom: [AgentProfile] = AgentConfig.load()

    /// Builtins plus agents.json entries; a custom slug overrides its builtin.
    static var all: [AgentProfile] {
        let customSlugs = Set(custom.map(\.slug))
        return builtin.filter { !customSlugs.contains($0.slug) } + custom
    }

    static func reloadCustom() {
        custom = AgentConfig.load()
    }
}

struct Organization: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var organizationID: UUID?
}

struct TerminalSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    let agent: AgentProfile
    let directory: String
    let worktreeBranch: String?
    var exited = false
    /// Process killed to free memory; resumes on demand with the agent's resume command.
    var hibernated = false

    var shortID: String { String(id.uuidString.prefix(4)).lowercased() }
}

extension TerminalSession: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, workspaceID, agent, directory, worktreeBranch, exited, hibernated
    }

    // Hand-rolled so state.json files written before a field existed still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        agent = try container.decode(AgentProfile.self, forKey: .agent)
        directory = try container.decode(String.self, forKey: .directory)
        worktreeBranch = try container.decodeIfPresent(String.self, forKey: .worktreeBranch)
        exited = try container.decodeIfPresent(Bool.self, forKey: .exited) ?? false
        hibernated = try container.decodeIfPresent(Bool.self, forKey: .hibernated) ?? false
    }
}

struct DBConnection: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case postgres, redis

        var id: String { rawValue }
        var label: String { self == .postgres ? "PostgreSQL" : "Redis" }
        var symbol: String { self == .postgres ? "cylinder.split.1x2" : "bolt.horizontal" }
        var defaultPort: Int { self == .postgres ? 5432 : 6379 }
        var tint: Color { self == .postgres ? Color(hex: 0x7FA3C4) : Color(hex: 0xC96A5F) }
    }

    let id: UUID
    let workspaceID: UUID
    var name: String
    var kind: Kind
    var host: String
    var port: Int
    // Console credentials; optional so pre-console state.json still decodes.
    // Stored plaintext in state.json, same trust model as ~/.pgpass.
    var username: String?
    var password: String?
    var database: String?
}
