import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            Backdrop()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 236)
                Rectangle().fill(OrkTheme.stroke).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.selection {
        case .workspace(let id):
            if let workspace = store.workspace(id: id) {
                WorkspaceView(workspace: workspace)
                    .id(workspace.id)
            } else {
                welcome
            }
        case .data:
            DataToolsView()
        case nil:
            welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [OrkTheme.cyan, OrkTheme.magenta], startPoint: .top, endPoint: .bottom)
                )
            Text("welcome to ork")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(OrkTheme.text)
            Text("Add a project folder and spawn agent sessions in isolated worktrees.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
            Button {
                pickWorkspaceFolder(store: store)
            } label: {
                Label("add workspace", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.cyan.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
