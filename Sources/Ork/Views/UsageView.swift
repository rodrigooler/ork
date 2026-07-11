import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SidebarToggleButton()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage")
                        .font(OrkFont.display(15))
                        .foregroundStyle(OrkTheme.cream)
                    Text("Tokens across your agent CLIs, last 14 days.")
                        .font(.system(size: 11))
                        .foregroundStyle(OrkTheme.stone)
                }
            }
            .padding(.leading, store.sidebarHidden ? 58 : 0)

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
        VStack(alignment: .leading, spacing: 12) {
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
            UsageBars(days: usage.days, tint: tint, height: 76, animated: true)
            HStack {
                if let first = usage.days.first {
                    Text(first.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 9))
                        .foregroundStyle(OrkTheme.faint)
                }
                Spacer()
                Text("5h \(TokenFormat.compact(usage.last5h)) · 7d \(TokenFormat.compact(usage.last7d)) · today \(TokenFormat.compact(usage.today))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
            if !usage.projects.isEmpty {
                Rectangle().fill(OrkTheme.hairline).frame(height: 1)
                projectBreakdown(usage.projects, tint: tint)
            }
        }
        .padding(14)
        .orkCard()
        .frame(maxWidth: 640)
    }

    /// Where the tokens went: top project dirs in the same window, with a
    /// bar proportional to the biggest spender.
    private func projectBreakdown(_ projects: [AgentUsage.Project], tint: Color) -> some View {
        let peak = max(projects.first?.tokens ?? 1, 1)
        return VStack(alignment: .leading, spacing: 5) {
            Text("By project")
                .font(OrkFont.display(9.5))
                .foregroundStyle(OrkTheme.stone)
            ForEach(projects.prefix(6)) { project in
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OrkTheme.cream)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)
                    Capsule()
                        .fill(tint.opacity(0.55))
                        .frame(width: max(3, 240 * CGFloat(project.tokens) / CGFloat(peak)), height: 5)
                    Spacer(minLength: 0)
                    Text(TokenFormat.compact(project.tokens))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                }
            }
            if projects.count > 6 {
                Text("+\(projects.count - 6) more")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(OrkTheme.faint)
            }
        }
    }
}

/// One bar per day, today highlighted. Shared between the Usage view and the menu bar panel.
struct UsageBars: View {
    let days: [AgentUsage.Day]
    let tint: Color
    var height: CGFloat = 72
    /// One-shot grow-from-baseline cascade. Only the full Usage page opts in;
    /// the glance panels are seen too often to animate.
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var grown: Bool { !animated || shown }

    var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                let isToday = index == days.count - 1
                Capsule()
                    .fill(isToday ? tint : tint.opacity(0.4))
                    .frame(height: max(4, height * CGFloat(day.tokens) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0.04, anchor: .bottom)
                    .opacity(grown ? 1 : 0)
                    .animation(.smooth(duration: 0.35).delay(Double(index) * 0.015), value: grown)
                    .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(TokenFormat.compact(day.tokens)) tokens")
            }
        }
        .frame(height: height, alignment: .bottom)
        .onAppear { shown = true }
    }
}
