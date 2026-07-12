import Foundation
import Logging
import NIOCore
import NIOPosix
import PostgresNIO
// RediStack 1.x predates Sendable audits; its connection types are event-loop bound.
@preconcurrency import RediStack

/// One-shot query execution against registered endpoints. Connects per run
/// and closes after: a dev console, not a driver.
enum QueryService {
    struct Table {
        var columns: [String] = []
        var rows: [[String]] = []
        var note = ""
    }

    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private static let logger = Logger(label: "ork.query")
    static let rowCap = 500

    // MARK: - Postgres

    static func postgres(_ connection: DBConnection, sql: String) async -> Result<Table, Error> {
        let config = PostgresConnection.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.username?.isEmpty == false ? connection.username! : "postgres",
            password: connection.password?.isEmpty == false ? connection.password : nil,
            database: connection.database?.isEmpty == false ? connection.database : nil,
            tls: .disable
        )
        do {
            let conn = try await PostgresConnection.connect(
                on: group.next(), configuration: config, id: 1, logger: logger
            ).get()
            do {
                // simpleQuery keeps the wire format textual, so any SQL renders as strings.
                let rows = try await conn.simpleQuery(sql).get()
                try? await conn.close().get()
                return .success(table(from: rows))
            } catch {
                try? await conn.close().get()
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }

    private static func table(from rows: [PostgresRow]) -> Table {
        var table = Table()
        guard let first = rows.first else {
            table.note = "OK, no rows"
            return table
        }
        table.columns = first.map(\.columnName)
        table.rows = rows.prefix(rowCap).map { row in
            row.map { cell in cell.bytes.map { String(buffer: $0) } ?? "NULL" }
        }
        table.note = rows.count > rowCap
            ? "\(rows.count) rows, showing first \(rowCap)"
            : "\(rows.count) \(rows.count == 1 ? "row" : "rows")"
        return table
    }

    // MARK: - Redis

    static func redis(_ connection: DBConnection, command line: String) async -> Result<String, Error> {
        let parts = tokenize(line)
        guard let command = parts.first else { return .success("") }
        let arguments = parts.dropFirst().map { $0.convertedToRESPValue() }
        do {
            let config = try RedisConnection.Configuration(
                hostname: connection.host,
                port: connection.port,
                password: connection.password?.isEmpty == false ? connection.password : nil
            )
            let conn = try await RedisConnection.make(configuration: config, boundEventLoop: group.next()).get()
            do {
                let reply = try await conn.send(command: command.uppercased(), with: arguments).get()
                _ = try? await conn.close().get()
                return .success(render(reply))
            } catch {
                _ = try? await conn.close().get()
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }

    /// redis-cli style rendering of a RESP reply.
    static func render(_ value: RESPValue) -> String {
        switch value {
        case .null:
            return "(nil)"
        case .simpleString(let buffer):
            return String(buffer: buffer)
        case .bulkString(let buffer):
            return buffer.map { String(buffer: $0) } ?? "(nil)"
        case .error(let error):
            return "(error) \(error.message)"
        case .integer(let int):
            return "(integer) \(int)"
        case .array(let items):
            guard !items.isEmpty else { return "(empty array)" }
            return items.enumerated()
                .map { "\($0.offset + 1)) \(render($0.element))" }
                .joined(separator: "\n")
        }
    }

    /// Splits a command line into arguments, honoring single and double quotes.
    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

/// Per-connection console history, most recent first. Its own small JSON so
/// state.json stays free of console noise.
enum ConsoleHistory {
    static let cap = 50

    /// Dedup (a recalled query moves to the top) and cap.
    static func pushed(_ query: String, onto history: [String]) -> [String] {
        var next = history.filter { $0 != query }
        next.insert(query, at: 0)
        return Array(next.prefix(cap))
    }

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("console-history.json")
    }()

    private static var cache: [UUID: [String]]?

    static func queries(for id: UUID) -> [String] {
        if cache == nil { cache = load() }
        return cache?[id] ?? []
    }

    static func record(_ query: String, for id: UUID) {
        var all = cache ?? load()
        all[id] = pushed(query, onto: all[id] ?? [])
        cache = all
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url) }
    }

    private static func load() -> [UUID: [String]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([UUID: [String]].self, from: data)) ?? [:]
    }
}
