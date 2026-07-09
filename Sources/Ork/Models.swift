import SwiftUI

struct AgentProfile: Identifiable, Codable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let command: String
    let symbol: String
    let tintHex: UInt32

    var tint: Color { Color(hex: tintHex) }

    static let builtin: [AgentProfile] = [
        AgentProfile(slug: "claude", name: "Claude Code", command: "claude", symbol: "sparkles", tintHex: 0xD97757),
        AgentProfile(slug: "codex", name: "Codex", command: "codex", symbol: "cpu", tintHex: 0x3EF08A),
        AgentProfile(slug: "opencode", name: "OpenCode", command: "opencode", symbol: "chevron.left.forwardslash.chevron.right", tintHex: 0x00E5FF),
        AgentProfile(slug: "gemini", name: "Gemini CLI", command: "gemini", symbol: "diamond", tintHex: 0x7AA5FF),
        AgentProfile(slug: "shell", name: "Shell", command: "exec zsh", symbol: "terminal", tintHex: 0xFFB454),
    ]
}

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
}

struct TerminalSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    let agent: AgentProfile
    let directory: String
    let worktreeBranch: String?
    var exited = false

    var shortID: String { String(id.uuidString.prefix(4)).lowercased() }
}

struct DBConnection: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case postgres, redis

        var id: String { rawValue }
        var label: String { self == .postgres ? "PostgreSQL" : "Redis" }
        var symbol: String { self == .postgres ? "cylinder.split.1x2" : "bolt.horizontal" }
        var defaultPort: Int { self == .postgres ? 5432 : 6379 }
        var tint: Color { self == .postgres ? Color(hex: 0x7AA5FF) : Color(hex: 0xFF5C7A) }
    }

    let id: UUID
    var name: String
    var kind: Kind
    var host: String
    var port: Int
}
