import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    sectionHeader
                    ForEach(store.workspaces) { workspaceRow($0) }
                    if store.workspaces.isEmpty {
                        addPlaceholder
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ork")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(OrkTheme.cream)
            Text("agent orchestrator")
                .font(.system(size: 10))
                .foregroundStyle(OrkTheme.faint)
        }
        .padding(.top, 44)
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private var sectionHeader: some View {
        HStack {
            Text("Projects")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(OrkTheme.faint)
            Spacer()
            Button {
                pickWorkspaceFolder(store: store)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.plain)
            .help("Add project folder")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        let isSelected = store.selectedWorkspaceID == workspace.id
        let count = store.sessions.filter { $0.workspaceID == workspace.id }.count
        return Button {
            store.selectedWorkspaceID = workspace.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? OrkTheme.clay : OrkTheme.faint)
                Text(workspace.name)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? OrkTheme.cream : OrkTheme.stone)
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(OrkTheme.overlay)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? OrkTheme.overlay : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from ork", role: .destructive) {
                store.removeWorkspace(workspace)
            }
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
        HStack(spacing: 6) {
            Circle()
                .fill(OrkTheme.moss)
                .frame(width: 5, height: 5)
            Text("v0.2.0 · local first")
                .font(.system(size: 9.5))
                .foregroundStyle(OrkTheme.faint)
        }
        .padding(14)
    }
}

func pickWorkspaceFolder(store: AppStore) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"
    panel.message = "Choose a project folder to orchestrate"
    if panel.runModal() == .OK, let url = panel.url {
        store.addWorkspace(at: url)
    }
}
