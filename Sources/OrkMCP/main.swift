import Foundation
import OrkMCPCore

// ork-mcp --session <uuid>: stdio MCP server wiring one Ork session to its
// agent team. Spawned by the agent CLI (claude --mcp-config), not by Ork.

let args = CommandLine.arguments
guard let flagIndex = args.firstIndex(of: "--session"), args.count > flagIndex + 1 else {
    FileHandle.standardError.write(Data("usage: ork-mcp --session <uuid>\n".utf8))
    exit(2)
}

let bridgeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Ork/mcp", isDirectory: true)
let server = MCPServer(sessionID: args[flagIndex + 1], bridgeDir: bridgeDir, version: "1.0")

// Newline-delimited JSON-RPC over stdio; notifications get no response.
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let response = server.handle(object),
          let data = try? JSONSerialization.data(withJSONObject: response) else { continue }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
