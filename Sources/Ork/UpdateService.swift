import AppKit
import SwiftUI

enum OrkVersion {
    /// Single source of truth; scripts/package.sh reads it for the bundle.
    static let current = "0.8.0"
}

/// Checks GitHub for a newer release on launch and, on request, swaps the
/// running Ork.app for it in place and relaunches. Bare-binary runs
/// (swift run, pre-0.8.0 folder layout) cannot be swapped, so those fall
/// back to opening the releases page.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum Phase: Equatable {
        case idle
        case available(String)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var latestZip: URL?

    private static let latestAPI = URL(string: "https://api.github.com/repos/rodrigooler/ork/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/rodrigooler/ork/releases/latest")!

    func checkOnLaunch() {
        Task { [weak self] in
            // Let the window settle first; the check is not urgent.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.check()
        }
    }

    /// Quiet on any failure: offline or rate-limited just means no badge.
    @MainActor
    func check() async {
        var request = URLRequest(url: Self.latestAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = Self.parseLatest(data),
              Self.isNewer(release.version, than: OrkVersion.current) else { return }
        latestZip = release.zip
        phase = .available(release.version)
    }

    /// tag_name and the arm64 zip asset out of GitHub's latest-release JSON.
    static func parseLatest(_ data: Data) -> (version: String, zip: URL)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let zip = assets
            .compactMap({ $0["browser_download_url"] as? String })
            .first(where: { $0.hasSuffix("macos-arm64.zip") })
            .flatMap(URL.init(string:)) else { return nil }
        return (version, zip)
    }

    /// Numeric compare per dot segment; missing segments count as zero.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    @MainActor
    func install() {
        guard case .available = phase, let zip = latestZip else { return }
        guard let appURL = Self.installedAppURL else {
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        phase = .installing
        Task.detached(priority: .userInitiated) {
            do {
                try await Self.replaceApp(at: appURL, withZip: zip)
                await MainActor.run { Self.relaunch(appURL) }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    static var installedAppURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// Downloads and unpacks the release, then swaps the .app directory.
    /// The running process keeps its open inodes, so replacing the bundle
    /// under it is safe; the old app is kept aside until the new one is in.
    private static func replaceApp(at appURL: URL, withZip zip: URL) async throws {
        let fm = FileManager.default
        let (tmpZip, _) = try await URLSession.shared.download(from: zip)
        let unpack = tmpZip.deletingLastPathComponent()
            .appendingPathComponent("ork-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: unpack) }
        try run("/usr/bin/ditto", "-x", "-k", tmpZip.path, unpack.path)
        guard let newApp = try fm.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInArchive
        }
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", newApp.path)
        let backup = appURL.deletingLastPathComponent().appendingPathComponent(".Ork.previous.app")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: appURL, to: backup)
        do {
            try fm.moveItem(at: newApp, to: appURL)
        } catch {
            try? fm.moveItem(at: backup, to: appURL)
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// The helper shell outlives this process; the delay keeps the old and
    /// new instances from overlapping (two Orks would fight over sessions).
    private static func relaunch(_ appURL: URL) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "sleep 2; /usr/bin/open \"\(appURL.path)\""]
        try? helper.run()
        NSApp.terminate(nil)
    }

    private static func run(_ launchPath: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(URL(fileURLWithPath: launchPath).lastPathComponent)
        }
    }

    enum UpdateError: LocalizedError {
        case noAppInArchive
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAppInArchive: "the release zip has no .app inside"
            case .commandFailed(let tool): "\(tool) failed"
            }
        }
    }
}
