import AppKit
import SwiftUI

/// Live view of the workspace agent team: members, the shared board, the
/// message log and a composer to message the team as 'user'.
struct TeamPane: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    @State private var board = ""
    @State private var log: [String] = []
    @State private var draft = ""
    @State private var recipient = "all"
    @State private var lastStamps: [Date?] = []

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
                    Rectangle().fill(OrkTheme.hairline).frame(height: 1)
                    composer
                }
            }
        }
        .background(OrkTheme.ink)
        .task(id: workspace.id) {
            lastStamps = []
            while !Task.isCancelled {
                if AppStore.deckWindowVisible { await refresh() }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// Each tick costs two stat calls; file contents are read (off the main
    /// thread) only when a modification date actually moved.
    private func refresh() async {
        let boardURL = TeamService.boardURL(workspace.id)
        let logURL = TeamService.logURL(workspace.id)
        let stamps = [boardURL, logURL].map {
            (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date
        }
        guard stamps != lastStamps else { return }
        lastStamps = stamps
        let loaded = await Task.detached(priority: .utility) { () -> (String, [String]) in
            let board = (try? String(contentsOf: boardURL, encoding: .utf8)) ?? ""
            let raw = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            return (board, raw.split(separator: "\n").suffix(200).map(String.init))
        }.value
        board = loaded.0
        log = loaded.1
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

    /// Talk to the team without typing into a member's terminal. Messages go
    /// through the regular outbox, so agents see them as coming from 'user'.
    private var composer: some View {
        HStack(spacing: 8) {
            Picker("", selection: $recipient) {
                Text("all").tag("all")
                ForEach(members) { member in
                    let name = TeamService.memberName(member)
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
            TextField("Message the team as 'user'", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(OrkTheme.cream)
                .onSubmit(send)
            if draft.count > TeamService.messageCharCap {
                Text("\(draft.count)/\(TeamService.messageCharCap)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.brick)
            }
            Button("Send", action: send)
                .controlSize(.small)
                .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OrkTheme.well)
        .onChange(of: members.map(TeamService.memberName)) { _, names in
            if recipient != "all", !names.contains(recipient) { recipient = "all" }
        }
    }

    private var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= TeamService.messageCharCap
    }

    private func send() {
        guard canSend else { return }
        TeamService.shared.sendFromUser(
            workspaceID: workspace.id,
            to: recipient,
            text: draft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        draft = ""
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
