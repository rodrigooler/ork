import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    @State private var renameTarget: Workspace?
    @State private var renameText = ""
    @State private var collapsedOrgs: Set<UUID> = []
    @State private var showNewOrgAlert = false
    @State private var newOrgName = ""
    @State private var renameOrgTarget: Organization?
    @State private var renameOrgText = ""
    @State private var moveToNewOrgWorkspace: Workspace?

    private var runningCount: Int {
        store.sessions.filter { !$0.exited }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.organizations) { org in
                        orgSection(org)
                    }

                    let ungrouped = store.ungroupedWorkspaces
                    sectionLabel("Projects", showAdd: true)
                    ForEach(ungrouped) { workspaceRow($0) }
                    if store.workspaces.isEmpty {
                        addPlaceholder
                    }
                    sectionLabel("Tools", showAdd: false)
                        .padding(.top, 18)
                    usageRow
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
            footer
        }
        .alert(
            "Rename project",
            isPresented: .init(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    store.renameWorkspace(target, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Display name only; the folder on disk keeps its name.")
        }
        .alert(
            "New organization",
            isPresented: $showNewOrgAlert
        ) {
            TextField("Name", text: $newOrgName)
            Button("Create") {
                let trimmed = newOrgName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let org = store.addOrganization(name: trimmed)
                if let ws = moveToNewOrgWorkspace {
                    store.moveWorkspace(ws, toOrganization: org.id)
                    moveToNewOrgWorkspace = nil
                }
                newOrgName = ""
            }
            Button("Cancel", role: .cancel) {
                newOrgName = ""
                moveToNewOrgWorkspace = nil
            }
        }
        .alert(
            "Rename organization",
            isPresented: .init(
                get: { renameOrgTarget != nil },
                set: { if !$0 { renameOrgTarget = nil } }
            )
        ) {
            TextField("Name", text: $renameOrgText)
            Button("Rename") {
                if let target = renameOrgTarget {
                    store.renameOrganization(target, to: renameOrgText)
                }
                renameOrgTarget = nil
            }
            Button("Cancel", role: .cancel) { renameOrgTarget = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            OrkMarkView(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("ork")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(OrkTheme.cream)
                Text("agent orchestrator")
                    .font(.system(size: 9))
                    .kerning(0.8)
                    .foregroundStyle(OrkTheme.faint)
            }
            Spacer()
        }
        .padding(.top, 46)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [OrkTheme.clay.opacity(0.35), OrkTheme.hairline, OrkTheme.hairline.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func orgSection(_ org: Organization) -> some View {
        let isCollapsed = collapsedOrgs.contains(org.id)
        let orgWorkspaces = store.workspaces(in: org.id)
        let orgRunning = store.sessions.filter { s in
            !s.exited && orgWorkspaces.contains { $0.id == s.workspaceID }
        }.count
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(OrkTheme.faint)
                    .frame(width: 10)
                Text(org.name.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(OrkTheme.stone)
                if orgRunning > 0 {
                    PulsingDot(color: OrkTheme.moss, size: 4)
                }
                Spacer()
                Button {
                    pickWorkspaceFolder(store: store, organizationID: org.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OrkTheme.stone)
                }
                .buttonStyle(.plain)
                .help("Add project to \(org.name)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.12)) {
                    if isCollapsed { collapsedOrgs.remove(org.id) }
                    else { collapsedOrgs.insert(org.id) }
                }
            }
            .contextMenu {
                Button("Rename…") {
                    renameOrgText = org.name
                    renameOrgTarget = org
                }
                Button("Delete organization", role: .destructive) {
                    store.removeOrganization(org)
                }
            }

            if !isCollapsed {
                ForEach(orgWorkspaces) { workspace in
                    workspaceRow(workspace)
                        .padding(.leading, 10)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func sectionLabel(_ title: String, showAdd: Bool) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(OrkTheme.faint)
            Spacer()
            if showAdd {
                Menu {
                    Button("Add project…") {
                        pickWorkspaceFolder(store: store)
                    }
                    Divider()
                    Button("New organization…") {
                        moveToNewOrgWorkspace = nil
                        newOrgName = ""
                        showNewOrgAlert = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OrkTheme.stone)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
                .help("Add project or organization")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        let count = store.sessions.filter { $0.workspaceID == workspace.id }.count
        let hasRunning = store.sessions.contains { $0.workspaceID == workspace.id && !$0.exited }
        return SidebarRow(
            symbol: "folder.fill",
            title: workspace.name,
            isSelected: store.selection == .workspace(workspace.id),
            action: { store.selection = .workspace(workspace.id) }
        ) {
            if count > 0 {
                HStack(spacing: 5) {
                    if hasRunning {
                        PulsingDot(color: OrkTheme.moss, size: 5)
                    }
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                }
            }
        }
        .contextMenu {
            Button("Rename…") {
                renameText = workspace.name
                renameTarget = workspace
            }
            if !store.organizations.isEmpty {
                Menu("Move to…") {
                    ForEach(store.organizations) { org in
                        Button(org.name) {
                            store.moveWorkspace(workspace, toOrganization: org.id)
                        }
                        .disabled(workspace.organizationID == org.id)
                    }
                    Divider()
                    if workspace.organizationID != nil {
                        Button("No organization") {
                            store.moveWorkspace(workspace, toOrganization: nil)
                        }
                    }
                }
            }
            Button("New organization…") {
                moveToNewOrgWorkspace = workspace
                newOrgName = ""
                showNewOrgAlert = true
            }
            Divider()
            Button("Remove from ork", role: .destructive) {
                store.removeWorkspace(workspace)
            }
        }
    }

    private var usageRow: some View {
        SidebarRow(
            symbol: "chart.bar.fill",
            title: "Usage",
            isSelected: store.selection == .usage,
            action: { store.selection = .usage }
        ) {
            EmptyView()
        }
    }

    private var addPlaceholder: some View {
        Button {
            pickWorkspaceFolder(store: store)
        } label: {
            Label("Add project", systemImage: "plus")
                .font(.system(size: 11.5))
                .foregroundStyle(OrkTheme.stone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(OrkTheme.raised.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if runningCount > 0 {
                PulsingDot(color: OrkTheme.moss, size: 5)
                Text(runningCount == 1 ? "1 agent at work" : "\(runningCount) agents at work")
                    .font(.system(size: 10))
                    .foregroundStyle(OrkTheme.stone)
            } else {
                Circle().fill(OrkTheme.faint).frame(width: 5, height: 5)
                Text("idle")
                    .font(.system(size: 10))
                    .foregroundStyle(OrkTheme.faint)
            }
            Spacer()
            Text("v0.4.0")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.faint)
        }
        .padding(14)
    }
}

struct SidebarRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let trailing: Trailing

    @State private var hovering = false

    init(
        symbol: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? OrkTheme.clay.opacity(0.16) : OrkTheme.overlay.opacity(hovering ? 0.9 : 0.55))
                    Image(systemName: symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? OrkTheme.clay : OrkTheme.stone)
                }
                .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected || hovering ? OrkTheme.cream : OrkTheme.stone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? OrkTheme.overlay : (hovering ? OrkTheme.overlay.opacity(0.45) : .clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(OrkTheme.clay)
                        .frame(width: 2.5, height: 18)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

func pickWorkspaceFolder(store: AppStore, organizationID: UUID? = nil) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"
    panel.message = "Choose a project folder to orchestrate"
    if panel.runModal() == .OK, let url = panel.url {
        store.addWorkspace(at: url, organizationID: organizationID)
    }
}
