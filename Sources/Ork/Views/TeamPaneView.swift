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
    @State private var roleEditorID: UUID?
    @State private var roleDraft = ""
    @State private var proposals: [TeamService.Proposal] = []

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
                    if !proposals.isEmpty {
                        Rectangle().fill(OrkTheme.hairline).frame(height: 1)
                        proposalsStrip
                    }
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
        proposals = TeamService.openProposals(workspace.id)
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
            Button("Spawn manager") {
                store.spawnManager(in: workspace)
            }
            .controlSize(.small)
            .help("A claude session that reads the project, designs the team and staffs it through approval-gated tools")
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
                            roleDraft = member.persona ?? ""
                            roleEditorID = member.id
                        } label: {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 8.5))
                                .foregroundStyle(member.persona == nil ? OrkTheme.faint : member.agent.tint)
                        }
                        .buttonStyle(.pressable)
                        .help(member.persona.map { "Role: \($0)" } ?? "Set a standing role")
                        .popover(isPresented: Binding(
                            get: { roleEditorID == member.id },
                            set: { if !$0 { roleEditorID = nil } }
                        )) { roleEditor(member) }
                        Button {
                            store.leaveTeam(member.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundStyle(OrkTheme.faint)
                        }
                        .buttonStyle(.pressable)
                        .help("Remove from team")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .orkCard(radius: 7)
                }
                Spacer()
                Toggle("Autopilot", isOn: Binding(
                    get: { store.autopilotWorkspaceIDs.contains(workspace.id) },
                    set: { _ in store.toggleAutopilot(workspace.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("The team reviews the project on a cycle and files improvement proposals; nothing runs without your approval, and cycles pause above the usage ceiling (Settings)")
                if !members.contains(where: { store.managerSessionIDs.contains($0.id) }) {
                    Button("Spawn manager") {
                        store.spawnManager(in: workspace)
                    }
                    .controlSize(.small)
                    .help("A claude session that designs and staffs this team through approval-gated tools; tell it what the project needs")
                }
                Button("Rebrief") {
                    store.rebriefTeam(workspace.id)
                }
                .controlSize(.small)
                .help("Resend the current protocol briefing to every member, e.g. after an Ork update")
                Button("Open board") {
                    NSWorkspace.shared.open(TeamService.boardURL(workspace.id))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Autopilot output waiting on the root user: approve turns a proposal
    /// into board tasks, reject archives it with a note to the coordinator.
    private var proposalsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("PROPOSALS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.faint)
                    .kerning(1.1)
                ForEach(proposals) { proposal in
                    HStack(spacing: 6) {
                        Text(proposal.title)
                            .font(.system(size: 10.5))
                            .foregroundStyle(OrkTheme.cream)
                            .lineLimit(1)
                            .frame(maxWidth: 260, alignment: .leading)
                        Button {
                            TeamService.shared.decideProposal(workspace.id, proposal: proposal, approved: true)
                            proposals.removeAll { $0.id == proposal.id }
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(OrkTheme.moss)
                        }
                        .help("Approve: the coordinator decomposes it into board tasks")
                        Button {
                            TeamService.shared.decideProposal(workspace.id, proposal: proposal, approved: false)
                            proposals.removeAll { $0.id == proposal.id }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(OrkTheme.brick)
                        }
                        .help("Reject: archived, never proposed again")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .orkCard(radius: 7)
                    .buttonStyle(.pressable)
                    .onTapGesture { NSWorkspace.shared.open(proposal.url) }
                    .help(proposal.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    /// Edits the member's standing role (persona): injected into the live
    /// terminal now and carried into every future team briefing.
    private func roleEditor(_ member: TerminalSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standing role for \(TeamService.memberName(member))")
                .font(OrkFont.display(11))
                .foregroundStyle(OrkTheme.cream)
            TextEditor(text: $roleDraft)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(width: 280, height: 84)
                .background(OrkTheme.well)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            HStack {
                Text("Applied now, kept for future briefings.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(OrkTheme.faint)
                Spacer()
                Button("Apply") {
                    store.configureAgent(member.id, persona: roleDraft, model: "", effort: "")
                    roleEditorID = nil
                }
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    private var boardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Board", symbol: "doc.text")
            kanbanStrip
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

    /// Board at a glance: three columns with counts, first few items each.
    /// The raw markdown below stays the source of truth.
    @ViewBuilder private var kanbanStrip: some View {
        let columns = TeamService.boardColumns(board)
        if !(columns.backlog.isEmpty && columns.tasks.isEmpty && columns.archive.isEmpty) {
            HStack(alignment: .top, spacing: 8) {
                kanbanColumn("Backlog", items: columns.backlog, tint: OrkTheme.stone)
                kanbanColumn("In progress", items: columns.tasks, tint: OrkTheme.clay)
                kanbanColumn("Done", items: columns.archive, tint: OrkTheme.moss)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private func kanbanColumn(_ title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title)
                    .font(OrkFont.display(9.5))
                    .foregroundStyle(OrkTheme.stone)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(items.isEmpty ? OrkTheme.faint : tint)
            }
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
                    .lineLimit(1)
            }
            if items.count > 4 {
                Text("+\(items.count - 4) more")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(OrkTheme.faint)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orkCard(radius: 8)
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

    // The agent char cap does not apply here: the user pastes a full demand
    // on purpose, and TeamService exempts the 'user' sender.
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
