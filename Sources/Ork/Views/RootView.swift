import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            OrkTheme.ink.ignoresSafeArea()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 232)
                    .background(OrkTheme.well.ignoresSafeArea())
                Rectangle().fill(OrkTheme.hairline).frame(width: 1).ignoresSafeArea()
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
        case .usage:
            UsageView()
        case nil:
            welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(OrkTheme.clay)
            Text("Welcome to ork")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(OrkTheme.cream)
            Text("Add a project and spawn agents, each in its own worktree.")
                .font(.system(size: 12))
                .foregroundStyle(OrkTheme.stone)
            Button {
                pickWorkspaceFolder(store: store)
            } label: {
                Label("Add project", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.clay)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
