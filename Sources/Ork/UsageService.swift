import Foundation

struct AgentUsage {
    struct Day {
        let date: Date
        var tokens: Int
    }

    struct Project: Identifiable {
        let name: String
        var tokens: Int
        var id: String { name }
    }

    var days: [Day] = []  // oldest first, one entry per day
    var last5h = 0        // rolling window, real timestamps
    var last7d = 0
    var projects: [Project] = []  // window total per project dir, biggest first
    var monthCost: Double?  // estimated USD this calendar month; nil when no priced model appeared

    var total: Int { days.reduce(0) { $0 + $1.tokens } }
    var today: Int { days.last?.tokens ?? 0 }
}

enum TokenFormat {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}

enum UsageService {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_read_input_tokens: Int?
                let cache_creation_input_tokens: Int?

                var total: Int {
                    (input_tokens ?? 0) + (output_tokens ?? 0)
                        + (cache_read_input_tokens ?? 0) + (cache_creation_input_tokens ?? 0)
                }
            }

            let id: String?
            let model: String?
            let usage: Usage?
        }

        let timestamp: String?
        let message: Message?
    }

    /// Published API prices, USD per million tokens, matched by model prefix.
    /// Cache reads bill at 0.1× input and cache writes at 1.25× input.
    private static let pricing: [(prefix: String, input: Double, output: Double)] = [
        ("claude-opus", 15, 75),
        ("claude-sonnet", 3, 15),
        ("claude-haiku", 1, 5),
    ]

    /// Estimated cost of one usage entry; nil for models without a known price.
    static func costUSD(model: String?, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double? {
        guard let model, let price = pricing.first(where: { model.hasPrefix($0.prefix) }) else { return nil }
        let inputSide = Double(input) + Double(cacheRead) * 0.1 + Double(cacheWrite) * 1.25
        return (inputSide * price.input + Double(output) * price.output) / 1_000_000
    }

    /// Sums token usage from Claude Code transcripts (~/.claude/projects/**/*.jsonl).
    /// Deduplicates streamed entries by message id; an approximation, not billing data.
    /// ponytail: loads each recent file whole; mtime filter keeps it bounded
    static func claudeCode(daysBack: Int = 14) -> AgentUsage? {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        var buckets: [Date: Int] = [:]
        var projectTokens: [String: Int] = [:]
        var seen = Set<String>()
        var foundAny = false
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
        var last5h = 0
        var last7d = 0
        var monthCost: Double?

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let mtime, mtime >= cutoff else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            foundAny = true
            // Transcripts live under one folder per project dir.
            let relative = url.path.dropFirst(root.path.count + 1)
            let projectDir = String(relative.prefix { $0 != "/" })
            for lineText in content.split(separator: "\n") {
                guard lineText.contains("\"usage\"") else { continue }
                guard let line = try? JSONDecoder().decode(Line.self, from: Data(lineText.utf8)),
                      let usage = line.message?.usage,
                      let timestamp = line.timestamp else { continue }
                if let id = line.message?.id {
                    if seen.contains(id) { continue }
                    seen.insert(id)
                }
                guard let date = fractional.date(from: timestamp) ?? plain.date(from: timestamp) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= cutoff else { continue }
                buckets[day, default: 0] += usage.total
                projectTokens[projectDir, default: 0] += usage.total
                if date >= fiveHoursAgo { last5h += usage.total }
                if date >= sevenDaysAgo { last7d += usage.total }
                if date >= monthStart, let cost = costUSD(
                    model: line.message?.model,
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0,
                    cacheWrite: usage.cache_creation_input_tokens ?? 0
                ) {
                    monthCost = (monthCost ?? 0) + cost
                }
            }
        }
        guard foundAny else { return nil }

        var days: [AgentUsage.Day] = []
        for offset in stride(from: daysBack - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            days.append(.init(date: day, tokens: buckets[day] ?? 0))
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let projects = projectTokens
            .map { AgentUsage.Project(name: projectDisplayName($0.key, home: home), tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        return AgentUsage(days: days, last5h: last5h, last7d: last7d, projects: projects, monthCost: monthCost)
    }

    /// Transcript folders encode the project path with '-' for '/'
    /// ("-Users-me-www-ork"); the encoding is lossy, so this only strips the
    /// home prefix for a readable label ("www-ork").
    static func projectDisplayName(_ encoded: String, home: String) -> String {
        let homePrefix = home.replacingOccurrences(of: "/", with: "-") + "-"
        return encoded.hasPrefix(homePrefix) ? String(encoded.dropFirst(homePrefix.count)) : encoded
    }
}
