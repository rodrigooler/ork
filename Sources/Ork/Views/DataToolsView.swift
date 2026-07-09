import SwiftUI

struct DataToolsView: View {
    @EnvironmentObject private var store: AppStore

    enum ProbeStatus { case checking, reachable, unreachable }

    @State private var name = ""
    @State private var kind: DBConnection.Kind = .postgres
    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var status: [UUID: ProbeStatus] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Data Grid")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(OrkTheme.text)
                Text("Live endpoints for your data infrastructure. Query consoles land next.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OrkTheme.dim)
            }

            addForm

            if store.connections.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.connections) { connectionCard($0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
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
                Label("add", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.cyan.opacity(0.8))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(OrkTheme.stroke, lineWidth: 1))
        .onChange(of: kind) { _, newKind in
            port = String(newKind.defaultPort)
        }
    }

    private func addConnection() {
        guard let portNumber = Int(port), !host.isEmpty else { return }
        let connection = DBConnection(
            id: UUID(),
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
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OrkTheme.text)
                Text("\(connection.host):\(String(connection.port))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.dim)
            }
            Spacer()
            statusBadge(for: connection)
            Button("probe") {
                probe(connection)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 10, design: .monospaced))
            Button {
                store.removeConnection(connection.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(OrkTheme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(connection.kind.tint.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder private func statusBadge(for connection: DBConnection) -> some View {
        switch status[connection.id] {
        case .checking:
            ProgressView().controlSize(.small)
        case .reachable:
            statusLabel("online", OrkTheme.green)
        case .unreachable:
            statusLabel("offline", OrkTheme.red)
        case nil:
            statusLabel("unknown", OrkTheme.dim)
        }
    }

    private func statusLabel(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 5, height: 5).shadow(color: tint, radius: 3)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(OrkTheme.dim)
            Text("No endpoints yet. Add your Postgres or Redis above.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundStyle(OrkTheme.stroke)
        )
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
