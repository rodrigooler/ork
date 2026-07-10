import AppKit
import SwiftUI

/// Live view of the workspace agent team: members, the shared board and the
/// message log. Read-only; agents own the files.
struct TeamPane: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    @State private var board = ""
    @State private var log: [String] = []

    private var members: [TerminalSession] {
        store.teamMembers(in: workspace.id)
    }

    var body: some View {
        Group {
            if members.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    memberStrip
                    Rectangle().fill(OrkTheme.hairline).frame(height: 1)
                    HSplitView {
                        boardView.frame(minWidth: 300)
                        logView.frame(minWidth: 260)
                    }
                }
            }
        }
        .background(OrkTheme.ink)
        .task(id: workspace.id) {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func refresh() {
        board = (try? String(contentsOf: TeamService.boardURL(workspace.id), encoding: .utf8)) ?? ""
        let raw = (try? String(contentsOf: TeamService.logURL(workspace.id), encoding: .utf8)) ?? ""
        log = raw.split(separator: "\n").suffix(200).map(String.init)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OrkTheme.faint)
            Text("No team yet")
                .font(OrkFont.display(12.5))
                .foregroundStyle(OrkTheme.cream)
            Text("Right-click a terminal and choose Join Team. Members message each other through Ork and share the board as common context.")
                .font(.system(size: 11))
                .foregroundStyle(OrkTheme.stone)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memberStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members) { member in
                    HStack(spacing: 6) {
                        Image(systemName: member.agent.symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(member.agent.tint)
                        Text(TeamService.memberName(member))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(OrkTheme.cream)
                        if member.hibernated {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 8.5))
                                .foregroundStyle(OrkTheme.faint)
                        }
                        Button {
                            store.leaveTeam(member.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundStyle(OrkTheme.faint)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from team")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .orkCard(radius: 7)
                }
                Spacer()
                Button("Open board") {
                    NSWorkspace.shared.open(TeamService.boardURL(workspace.id))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var boardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Board", symbol: "doc.text")
            ScrollView {
                Text(board.isEmpty ? "Board is empty." : board)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(board.isEmpty ? OrkTheme.faint : OrkTheme.stone)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Messages", symbol: "bubble.left.and.bubble.right")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if log.isEmpty {
                        Text("No messages yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(OrkTheme.faint)
                    }
                    ForEach(log.indices, id: \.self) { index in
                        Text(log[index])
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(OrkTheme.stone)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
    }

    private func paneTitle(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(OrkTheme.faint)
            Text(title)
                .font(OrkFont.display(11))
                .foregroundStyle(OrkTheme.cream)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OrkTheme.well)
    }
}
