import Foundation

/// A question an agent is showing in its terminal right now, waiting on a key.
struct PendingPrompt: Equatable {
    struct Option: Equatable {
        let key: String    // the keystroke that picks it ("1"..."9")
        let label: String
    }

    let title: String
    let options: [Option]
}

/// Recognizes claude-style choice prompts (permissions, plan approval,
/// questions) in the visible tail of a terminal. Pure text matching so it is
/// unit-testable; reading the buffer and sending keys live in the callers.
enum PromptWatchService {
    /// Box-drawing frame characters claude wraps prompts in.
    private static let frame = CharacterSet(charactersIn: "│┃║╭╮╰╯─═├┤")

    /// Detects a pending prompt in the last visible lines, bottom of screen.
    /// Requires the claude shape: a question line ending in "?", two or more
    /// numbered options right under it, and the ❯ selector on one of them —
    /// strict on purpose, a numbered list in normal output must not match.
    static func detect(lines: [String]) -> PendingPrompt? {
        let cleaned = lines.map { line in
            line.components(separatedBy: frame).joined().trimmingCharacters(in: .whitespaces)
        }

        var options: [PendingPrompt.Option] = []
        var sawSelector = false
        var firstOptionIndex: Int?
        var gap = 0
        for (index, line) in cleaned.enumerated() {
            guard let match = optionMatch(line) else {
                // Wrapped option text continues on unnumbered lines; a small
                // gap keeps the block together, a large one starts over.
                if !options.isEmpty {
                    gap += line.isEmpty ? 2 : 1
                    if gap > 4 { options = []; sawSelector = false; firstOptionIndex = nil; gap = 0 }
                }
                continue
            }
            if match.number != options.count + 1 {
                options = []
                sawSelector = false
                firstOptionIndex = nil
            }
            gap = 0
            if match.number == options.count + 1 {
                if options.isEmpty { firstOptionIndex = index }
                options.append(.init(key: "\(match.number)", label: match.label))
                sawSelector = sawSelector || match.selected
            }
        }
        guard options.count >= 2, sawSelector, let firstOptionIndex else { return nil }

        for index in stride(from: firstOptionIndex - 1, through: max(0, firstOptionIndex - 8), by: -1) {
            let line = cleaned[index]
            if line.hasSuffix("?") { return PendingPrompt(title: line, options: options) }
        }
        return nil
    }

    private static func optionMatch(_ line: String) -> (number: Int, label: String, selected: Bool)? {
        var text = line
        let selected = text.hasPrefix("❯")
        if selected { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard let dot = text.firstIndex(of: "."), let number = Int(text[..<dot]), (1...9).contains(number) else {
            return nil
        }
        let label = text[text.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        return (number, label, selected)
    }
}
