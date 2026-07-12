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
    @State private var username = ""
    @State private var password = ""
    @State private var database = ""
    @State private var status: [UUID: ProbeStatus] = [:]
    @State private var consoleID: UUID?

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
                        ForEach(connections) { connection in
                            VStack(spacing: 0) {
                                connectionCard(connection)
                                if consoleID == connection.id {
                                    QueryConsole(connection: connection)
                                }
                            }
                        }
                    }
                }
                .animation(OrkMotion.layout, value: connections.map(\.id))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var addForm: some View {
        VStack(spacing: 8) {
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
            HStack(spacing: 8) {
                if kind == .postgres {
                    TextField("user", text: $username).orkField().frame(width: 120)
                    SecureField("password", text: $password).orkField().frame(width: 120)
                    TextField("database", text: $database).orkField().frame(width: 140)
                } else {
                    SecureField("password (optional)", text: $password).orkField().frame(width: 180)
                }
                Spacer()
            }
        }
        .padding(10)
        .orkCard()
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
            port: portNumber,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password,
            database: database.isEmpty ? nil : database
        )
        store.addConnection(connection)
        name = ""
        password = ""
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
            Button("Console") {
                withAnimation(OrkMotion.state) {
                    consoleID = consoleID == connection.id ? nil : connection.id
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 10))
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
            .buttonStyle(.pressable)
        }
        .padding(12)
        .orkCard()
        .transition(.scale(scale: 0.97).combined(with: .opacity))
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
                .font(OrkFont.display(12.5))
                .foregroundStyle(OrkTheme.cream)
            Text("Add the Postgres or Redis this project talks to, then open its console to run queries.")
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

/// SQL editor or Redis command line against one endpoint, results rendered
/// as a monospaced grid the way psql and redis-cli would.
struct QueryConsole: View {
    let connection: DBConnection

    @State private var input = ""
    @State private var running = false
    @State private var output: [String] = []
    @State private var note = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if connection.kind == .postgres {
                TextEditor(text: $input)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 72)
                    .padding(6)
                    .background(OrkTheme.well)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                HStack(spacing: 8) {
                    Button(running ? "Running…" : "Run") { run() }
                        .buttonStyle(.borderedProminent)
                        .tint(OrkTheme.clay)
                        .controlSize(.small)
                        .disabled(running || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    historyMenu
                    Text("Cmd+Return runs. Results cap at \(QueryService.rowCap) rows.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(OrkTheme.faint)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("GET mykey", text: $input)
                        .orkField()
                        .font(.system(size: 11.5, design: .monospaced))
                        .onSubmit { run() }
                    Button(running ? "…" : "Send") { run() }
                        .buttonStyle(.borderedProminent)
                        .tint(OrkTheme.clay)
                        .controlSize(.small)
                        .disabled(running || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    historyMenu
                }
            }
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(failed ? OrkTheme.brick : OrkTheme.faint)
                    .textSelection(.enabled)
            }
            if !output.isEmpty {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(output.indices, id: \.self) { index in
                            Text(output[index])
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(index == 0 && connection.kind == .postgres ? OrkTheme.cream : OrkTheme.stone)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 260)
                .background(OrkTheme.well)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
        .orkCard(radius: 8, fill: OrkTheme.overlay)
        .padding(.top, 4)
        .transition(.opacity)
    }

    /// Recall a past query into the editor; failed queries are kept too,
    /// recall-and-fix is the common loop.
    private var historyMenu: some View {
        let recent = ConsoleHistory.queries(for: connection.id)
        return Menu {
            ForEach(recent, id: \.self) { query in
                Button(String(query.prefix(60))) { input = query }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
        }
        .controlSize(.small)
        .frame(width: 44)
        .disabled(recent.isEmpty)
        .help("Query history for this connection")
    }

    private func run() {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !running else { return }
        ConsoleHistory.record(query, for: connection.id)
        running = true
        failed = false
        note = ""
        output = []
        let connection = connection
        Task {
            if connection.kind == .postgres {
                switch await QueryService.postgres(connection, sql: query) {
                case .success(let table):
                    output = Self.grid(table)
                    note = table.note
                case .failure(let error):
                    failed = true
                    note = String(describing: error)
                }
            } else {
                switch await QueryService.redis(connection, command: query) {
                case .success(let reply):
                    output = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                case .failure(let error):
                    failed = true
                    note = String(describing: error)
                }
            }
            running = false
        }
    }

    /// Pads cells into aligned monospaced lines, psql style.
    static func grid(_ table: QueryService.Table, cellCap: Int = 60) -> [String] {
        guard !table.columns.isEmpty else { return [] }
        let all = [table.columns] + table.rows
        let clipped = all.map { row in
            row.map { $0.count > cellCap ? String($0.prefix(cellCap - 1)) + "…" : $0 }
        }
        var widths = [Int](repeating: 0, count: table.columns.count)
        for row in clipped {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return clipped.map { row in
            row.enumerated()
                .map { index, cell in cell.padding(toLength: widths[index], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
        }
    }
}
