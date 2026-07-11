import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var settings = OrkSettings.shared

    @State private var renameTarget: Workspace?
    @State private var renameText = ""
    @State private var collapsedOrgs: Set<UUID> = []
    @State private var showNewOrgAlert = false
    @State private var newOrgName = ""
    @State private var renameOrgTarget: Organization?
    @State private var renameOrgText = ""
    @State private var moveToNewOrgWorkspace: Workspace?
    @State private var dropHover: UUID?

    private var runningCount: Int {
        store.sessions.filter { !$0.exited }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.visibleOrganizations) { org in
                        orgSection(org)
                    }

                    let ungrouped = store.visibleUngroupedWorkspaces
                    if !ungrouped.isEmpty || store.visibleOrganizations.isEmpty {
                        sectionLabel("Projects")
                    }
                    ForEach(ungrouped) { workspaceRow($0) }
                    if store.workspaces.isEmpty {
                        addPlaceholder
                    }
                    sectionLabel("Tools")
                        .padding(.top, 10)
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
            BrandLogo(height: 46)
            Text("agent\norchestrator")
                .font(OrkFont.display(8, weight: .medium))
                .kerning(1.1)
                .lineSpacing(3)
                .textCase(.uppercase)
                .foregroundStyle(OrkTheme.stone)
            Spacer()
            addMenu
        }
        .padding(.top, 30)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// Global add entry point; also the only one when every project lives
    /// inside an organization and the Projects section is hidden.
    private var addMenu: some View {
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OrkTheme.stone)
                .frame(width: 22, height: 22)
                .background(OrkTheme.overlay.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.pressable)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add project or organization")
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.faint)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                Text(org.name.uppercased())
                    .font(OrkFont.display(8, weight: .medium))
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
                .buttonStyle(.pressable)
                .help("Add project to \(org.name)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(dropHover == org.id ? OrkTheme.clay.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OrkMotion.state) {
                    if isCollapsed { collapsedOrgs.remove(org.id) }
                    else { collapsedOrgs.insert(org.id) }
                }
            }
            .onDrag { NSItemProvider(object: "org:\(org.id.uuidString)" as NSString) }
            .onDrop(of: [.plainText], delegate: SidebarDrop(targetID: org.id, hovered: $dropHover) { payload in
                handleDrop(payload, ontoOrg: org)
            })
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
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(OrkFont.display(8, weight: .medium))
            .kerning(1.2)
            .foregroundStyle(OrkTheme.faint)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        SidebarRow(
            symbol: "folder.fill",
            title: workspace.name,
            isSelected: store.selection == .workspace(workspace.id),
            action: { store.selection = .workspace(workspace.id) }
        ) { hovering in
            HStack(spacing: 5) {
                // Move menu lists every organization, so privacy mode hides it.
                if !store.organizations.isEmpty && !settings.privacyMode {
                    // Action reveals on hover; status (dots) stays put.
                    moveMenu(for: workspace)
                        .opacity(hovering ? 1 : 0)
                }
                sessionDots(for: workspace)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(dropHover == workspace.id ? OrkTheme.clay.opacity(0.14) : .clear)
        )
        .onDrag { NSItemProvider(object: "ws:\(workspace.id.uuidString)" as NSString) }
        .onDrop(of: [.plainText], delegate: SidebarDrop(targetID: workspace.id, hovered: $dropHover) { payload in
            handleDrop(payload, ontoWorkspace: workspace)
        })
        .contextMenu {
            Button("Rename…") {
                renameText = workspace.name
                renameTarget = workspace
            }
            if !store.organizations.isEmpty && !settings.privacyMode {
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

    private func moveMenu(for workspace: Workspace) -> some View {
        Menu {
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
            Button("New organization…") {
                moveToNewOrgWorkspace = workspace
                newOrgName = ""
                showNewOrgAlert = true
            }
        } label: {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OrkTheme.faint)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move to organization")
    }

    /// Agent-tinted presence dots, one per session (max 4), dimmed once exited.
    @ViewBuilder private func sessionDots(for workspace: Workspace) -> some View {
        let wsSessions = store.sessions.filter { $0.workspaceID == workspace.id }
        if !wsSessions.isEmpty {
            HStack(spacing: 3) {
                ForEach(wsSessions.prefix(4)) { session in
                    Circle()
                        .fill(session.agent.tint.opacity(session.exited ? 0.35 : 1))
                        .frame(width: 4.5, height: 4.5)
                }
                if wsSessions.count > 4 {
                    Text("+\(wsSessions.count - 4)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(OrkTheme.faint)
                }
            }
        }
    }

    // MARK: - Drag and drop reordering

    private func handleDrop(_ payload: String, ontoOrg org: Organization) {
        if payload.hasPrefix("org:"), let id = UUID(uuidString: String(payload.dropFirst(4))) {
            withAnimation(OrkMotion.state) { store.reorderOrganization(id, onto: org.id) }
        } else if payload.hasPrefix("ws:"), let id = UUID(uuidString: String(payload.dropFirst(3))),
                  let workspace = store.workspace(id: id) {
            withAnimation(OrkMotion.state) { store.moveWorkspace(workspace, toOrganization: org.id) }
        }
    }

    private func handleDrop(_ payload: String, ontoWorkspace target: Workspace) {
        guard payload.hasPrefix("ws:"),
              let id = UUID(uuidString: String(payload.dropFirst(3))), id != target.id else { return }
        withAnimation(OrkMotion.state) { store.reorderWorkspace(id, onto: target.id) }
    }

    private var usageRow: some View {
        SidebarRow(
            symbol: "chart.bar.fill",
            title: "Usage",
            isSelected: store.selection == .usage,
            action: { store.selection = .usage }
        ) { _ in
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
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if runningCount > 0 {
                PulsingDot(color: OrkTheme.moss, size: 5)
                Text(runningCount == 1 ? "1 agent at work" : "\(runningCount) agents at work")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
        .animation(OrkMotion.state, value: runningCount)
    }
}

struct SidebarRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let trailing: (Bool) -> Trailing

    @State private var hovering = false

    init(
        symbol: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping (Bool) -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? OrkTheme.clay.opacity(0.16) : OrkTheme.overlay.opacity(hovering ? 0.9 : 0.55))
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? OrkTheme.clay : OrkTheme.stone)
                }
                .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected || hovering ? OrkTheme.cream : OrkTheme.stone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing(hovering)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? OrkTheme.overlay : (hovering ? OrkTheme.overlay.opacity(0.45) : .clear))
            )
            // Whole row is a hit target, not just the pixels with text.
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
        .animation(OrkMotion.hover, value: hovering)
        .animation(OrkMotion.hover, value: isSelected)
    }
}

/// Reorder drop target: highlights the hovered row and hands the dragged
/// payload ("org:<uuid>" or "ws:<uuid>") to the row's handler.
struct SidebarDrop: DropDelegate {
    let targetID: UUID
    @Binding var hovered: UUID?
    let accept: (String) -> Void

    func dropEntered(info: DropInfo) { hovered = targetID }
    func dropExited(info: DropInfo) { if hovered == targetID { hovered = nil } }

    func performDrop(info: DropInfo) -> Bool {
        hovered = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String else { return }
            DispatchQueue.main.async { accept(payload) }
        }
        return true
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
