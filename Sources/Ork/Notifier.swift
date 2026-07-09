import Foundation

enum Notifier {
    /// osascript needs no bundle or entitlements, which a bare SPM executable lacks.
    /// ponytail: notifications show Script Editor as source; UNUserNotificationCenter once ork ships as a real .app
    static func notify(title: String, body: String) {
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
