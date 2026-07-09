import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("WORKSPACES", showAdd: true)
                    ForEach(store.workspaces) { workspaceRow($0) }
                    if store.workspaces.isEmpty {
                        addPlaceholder
                    }
                    sectionHeader("TOOLS", showAdd: false)
                        .padding(.top, 16)
                    dataRow
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ORK")
                .font(.system(size: 21, weight: .black, design: .monospaced))
                .kerning(7)
                .foregroundStyle(
                    LinearGradient(colors: [OrkTheme.cyan, OrkTheme.magenta], startPoint: .leading, endPoint: .trailing)
                )
            Text("agent orchestrator")
                .font(.system(size: 9, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(OrkTheme.dim)
        }
        .padding(.top, 42)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func sectionHeader(_ title: String, showAdd: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(OrkTheme.dim)
            Spacer()
            if showAdd {
                Button {
                    pickWorkspaceFolder(store: store)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(OrkTheme.cyan)
                }
                .buttonStyle(.plain)
                .help("Add workspace folder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        let isSelected = store.selection == .workspace(workspace.id)
        let count = store.sessions.filter { $0.workspaceID == workspace.id }.count
        return Button {
            store.selection = .workspace(workspace.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? OrkTheme.cyan : OrkTheme.dim)
                Text(workspace.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? OrkTheme.text : OrkTheme.dim)
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(OrkTheme.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(OrkTheme.cyan.opacity(0.9))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? OrkTheme.cyan.opacity(0.35) : .clear, lineWidth: 1)
            )
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
            Label("add workspace", systemImage: "plus")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(OrkTheme.stroke)
                )
        }
        .buttonStyle(.plain)
    }

    private var dataRow: some View {
        let isSelected = store.selection == .data
        return Button {
            store.selection = .data
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? OrkTheme.cyan : OrkTheme.dim)
                Text("data grid")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? OrkTheme.text : OrkTheme.dim)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? OrkTheme.cyan.opacity(0.35) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(OrkTheme.green)
                .frame(width: 5, height: 5)
                .shadow(color: OrkTheme.green, radius: 3)
            Text("v0.1.0 · local first")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
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
