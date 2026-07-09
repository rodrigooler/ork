import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(OrkTheme.cream)
                Text("Tokens across your agent CLIs, last 14 days.")
                    .font(.system(size: 11))
                    .foregroundStyle(OrkTheme.stone)
            }

            if let usage = store.claudeUsage {
                agentCard(name: "Claude Code", symbol: "sparkles", tint: OrkTheme.clay, usage: usage)
            } else if store.usageScanned {
                Text("No Claude Code transcripts found in ~/.claude.")
                    .font(.system(size: 11))
                    .foregroundStyle(OrkTheme.stone)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning transcripts…")
                        .font(.system(size: 11))
                        .foregroundStyle(OrkTheme.stone)
                }
            }

            Text("Codex and OpenCode usage land next.")
                .font(.system(size: 10))
                .foregroundStyle(OrkTheme.faint)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { store.loadUsageIfNeeded() }
    }

    private func agentCard(name: String, symbol: String, tint: Color, usage: AgentUsage) -> some View {
        let peak = max(usage.days.map(\.tokens).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OrkTheme.cream)
                Spacer()
                Text("\(TokenFormat.compact(usage.total)) · 14d")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(usage.days.indices, id: \.self) { index in
                    let day = usage.days[index]
                    let isToday = index == usage.days.count - 1
                    Capsule()
                        .fill(isToday ? tint : tint.opacity(0.4))
                        .frame(height: max(5, 72 * CGFloat(day.tokens) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(TokenFormat.compact(day.tokens)) tokens")
                }
            }
            .frame(height: 76, alignment: .bottom)
            HStack {
                if let first = usage.days.first {
                    Text(first.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 9))
                        .foregroundStyle(OrkTheme.faint)
                }
                Spacer()
                Text("today \(TokenFormat.compact(usage.today))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
        }
        .padding(14)
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OrkTheme.hairline, lineWidth: 1))
        .frame(maxWidth: 640)
    }
}
