import Foundation

/// One rendered row of the team chat, parsed from log.md.
struct ChatEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case message(sender: String, recipient: String)
        case system
    }

    let id: Int
    let time: String
    let kind: Kind
    var content: String
    var annotations: [String] = []

    var sender: String? {
        if case .message(let sender, _) = kind { return sender }
        return nil
    }

    var recipient: String? {
        if case .message(_, let recipient) = kind { return recipient }
        return nil
    }
}

/// log.md grammar: entries start with "- [HH:MM:SS] ". "sender → recipient:
/// content" is a message, anything else a system event. Indented "(...)"
/// lines annotate the previous entry (bounced, spilled, control notes); any
/// other line continues the previous entry's content.
enum TeamChat {
    static func parse(_ lines: [String]) -> [ChatEntry] {
        var entries: [ChatEntry] = []
        for line in lines {
            if let entry = parseEntryStart(line, id: entries.count) {
                entries.append(entry)
            } else if entries.isEmpty {
                continue
            } else if line.hasPrefix("  ("), line.trimmingCharacters(in: .whitespaces).hasSuffix(")") {
                let note = line.trimmingCharacters(in: .whitespaces)
                entries[entries.count - 1].annotations.append(String(note.dropFirst().dropLast()))
            } else {
                entries[entries.count - 1].content += "\n" + line
            }
        }
        return entries
    }

    private static func parseEntryStart(_ line: String, id: Int) -> ChatEntry? {
        guard line.hasPrefix("- ["), let close = line.firstIndex(of: "]") else { return nil }
        let time = String(line[line.index(line.startIndex, offsetBy: 3)..<close])
        guard let restStart = line.index(close, offsetBy: 2, limitedBy: line.endIndex) else { return nil }
        let rest = String(line[restStart...])
        // The sender never contains the arrow, so the first one splits safely
        // even when the content carries its own.
        if let arrow = rest.range(of: " → "),
           let colon = rest.range(of: ": ", range: arrow.upperBound..<rest.endIndex) {
            let sender = String(rest[..<arrow.lowerBound])
            let recipient = String(rest[arrow.upperBound..<colon.lowerBound])
            let content = String(rest[colon.upperBound...])
            return ChatEntry(id: id, time: time, kind: .message(sender: sender, recipient: recipient), content: content)
        }
        return ChatEntry(id: id, time: time, kind: .system, content: rest)
    }
}
