import SwiftUI

/// Data endpoints scoped to one workspace: lives inside the project, like a plugin pane.
struct DataPane: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    enum ProbeStatus { case checking, reachable, unreachable }

    @State private var name = ""
    @State private var kind: DBConnection.Kind = .postgres
    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var status: [UUID: ProbeStatus] = [:]

    private var connections: [DBConnection] {
        store.connections(for: workspace.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            addForm
            if connections.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(connections) { connectionCard($0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var addForm: some View {
        HStack(spacing: 8) {
            Picker("", selection: $kind) {
                ForEach(DBConnection.Kind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            TextField("name", text: $name).orkField().frame(width: 150)
            TextField("host", text: $host).orkField()
            TextField("port", text: $port).orkField().frame(width: 70)
            Button {
                addConnection()
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.clay)
        }
        .padding(10)
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OrkTheme.hairline, lineWidth: 1))
        .onChange(of: kind) { _, newKind in
            port = String(newKind.defaultPort)
        }
    }

    private func addConnection() {
        guard let portNumber = Int(port), !host.isEmpty else { return }
        let connection = DBConnection(
            id: UUID(),
            workspaceID: workspace.id,
            name: name.isEmpty ? "\(kind.rawValue)-local" : name,
            kind: kind,
            host: host,
            port: portNumber
        )
        store.addConnection(connection)
        name = ""
    }

    private func connectionCard(_ connection: DBConnection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: connection.kind.symbol)
                .font(.system(size: 14))
                .foregroundStyle(connection.kind.tint)
                .frame(width: 34, height: 34)
                .background(connection.kind.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrkTheme.cream)
                Text("\(connection.host):\(String(connection.port))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
            Spacer()
            statusBadge(for: connection)
            Button("Probe") {
                probe(connection)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 10))
            Button {
                store.removeConnection(connection.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func statusBadge(for connection: DBConnection) -> some View {
        switch status[connection.id] {
        case .checking:
            ProgressView().controlSize(.small)
        case .reachable:
            statusLabel("online", OrkTheme.moss)
        case .unreachable:
            statusLabel("offline", OrkTheme.brick)
        case nil:
            statusLabel("unknown", OrkTheme.faint)
        }
    }

    private func statusLabel(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(tint)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OrkTheme.faint)
            Text("No endpoints for this project")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(OrkTheme.cream)
            Text("Add the Postgres or Redis this project talks to. Query consoles land in a next release.")
                .font(.system(size: 11))
                .foregroundStyle(OrkTheme.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func probe(_ connection: DBConnection) {
        status[connection.id] = .checking
        let host = connection.host
        let port = UInt16(exactly: connection.port) ?? 0
        Task {
            let ok = await Reachability.check(host: host, port: port)
            await MainActor.run {
                status[connection.id] = ok ? .reachable : .unreachable
            }
        }
    }
}
