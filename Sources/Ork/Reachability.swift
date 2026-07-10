import Foundation
import Network
import os

enum Reachability {
    /// Plain TCP connect probe with a 3 second timeout. Proves the port answers, not that auth works.
    static func check(host: String, port: UInt16) async -> Bool {
        guard port > 0, let nwPort = NWEndpoint.Port(rawValue: port), !host.isEmpty else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ork.probe")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            // The continuation must resume exactly once whether the state
            // handler or the timeout wins; the lock makes that race safe.
            let finished = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ ok: Bool) {
                let first = finished.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .waiting:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}
