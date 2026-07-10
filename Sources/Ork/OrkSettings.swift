import SwiftUI

enum Appearance: String, CaseIterable {
    case dark, light
}

/// User preferences, persisted in UserDefaults. App data stays in state.json.
final class OrkSettings: ObservableObject {
    static let shared = OrkSettings()

    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            OrkTheme.light = appearance == .light
            TerminalRegistry.shared.applyAppearance()
        }
    }
    @Published var terminalFontName: String {
        didSet {
            defaults.set(terminalFontName, forKey: "terminalFontName")
            TerminalRegistry.shared.applyFont()
        }
    }
    @Published var terminalFontSize: Double {
        didSet {
            defaults.set(terminalFontSize, forKey: "terminalFontSize")
            TerminalRegistry.shared.applyFont()
        }
    }
    @Published var defaultWorktree: Bool {
        didSet { defaults.set(defaultWorktree, forKey: "defaultWorktree") }
    }
    @Published var freezeEnabled: Bool {
        didSet { defaults.set(freezeEnabled, forKey: "freezeEnabled") }
    }
    @Published var freezeMinutes: Int {
        didSet { defaults.set(freezeMinutes, forKey: "freezeMinutes") }
    }
    @Published var notifyOnExit: Bool {
        didSet { defaults.set(notifyOnExit, forKey: "notifyOnExit") }
    }
    @Published var confirmCloseRunning: Bool {
        didSet { defaults.set(confirmCloseRunning, forKey: "confirmCloseRunning") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
        terminalFontName = defaults.string(forKey: "terminalFontName") ?? ""
        terminalFontSize = defaults.object(forKey: "terminalFontSize") as? Double ?? 12.5
        defaultWorktree = defaults.object(forKey: "defaultWorktree") as? Bool ?? true
        freezeEnabled = defaults.object(forKey: "freezeEnabled") as? Bool ?? true
        freezeMinutes = defaults.object(forKey: "freezeMinutes") as? Int ?? 10
        notifyOnExit = defaults.object(forKey: "notifyOnExit") as? Bool ?? true
        confirmCloseRunning = defaults.object(forKey: "confirmCloseRunning") as? Bool ?? true
        OrkTheme.light = appearance == .light
    }
}
