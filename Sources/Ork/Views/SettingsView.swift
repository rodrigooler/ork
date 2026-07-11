import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearancePane()
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            TerminalPane()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            BehaviorPane()
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            AgentsPane()
                .tabItem { Label("Agents", systemImage: "person.2") }
        }
        .frame(width: 460)
    }
}

private struct AgentsPane: View {
    @State private var customCount = AgentProfile.custom.count

    var body: some View {
        Form {
            LabeledContent("Custom agents", value: "\(customCount)")
            HStack {
                Button("Edit agents.json") {
                    NSWorkspace.shared.open(AgentConfig.url)
                }
                Button("Reload") {
                    AgentProfile.reloadCustom()
                    customCount = AgentProfile.custom.count
                }
            }
            Text("""
            Each entry needs slug, name and command. Optional: symbol (SF Symbol name), \
            tint ("#RRGGBB") and resumeCommand. A custom slug overrides the builtin agent. \
            Example:
            [{"slug": "aider", "name": "Aider", "command": "aider", "tint": "#7FA3C4"}]
            """)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct AppearancePane: View {
    @EnvironmentObject private var settings: OrkSettings

    var body: some View {
        Form {
            Picker("Theme", selection: $settings.appearance) {
                Text("Dark").tag(Appearance.dark)
                Text("Light").tag(Appearance.light)
            }
            .pickerStyle(.segmented)
            Text("Applies to the whole app, terminals included.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct TerminalPane: View {
    @EnvironmentObject private var settings: OrkSettings

    private static let monospaceFamilies: [String] = NSFontManager.shared
        .availableFontFamilies
        .filter { NSFont(name: $0, size: 12)?.isFixedPitch == true }
        .sorted()

    var body: some View {
        Form {
            Picker("Font", selection: $settings.terminalFontName) {
                Text("Automatic").tag("")
                Divider()
                ForEach(Self.monospaceFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            HStack {
                Slider(value: $settings.terminalFontSize, in: 10...20, step: 0.5) {
                    Text("Size")
                }
                Text(String(format: "%.1f pt", settings.terminalFontSize))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            LabeledContent("Preview") {
                Text("claude --continue  0O 1lI {} ->")
                    .font(previewFont)
                    .lineLimit(1)
            }
            Text("Automatic picks the first installed of JetBrains Mono, Fira Code, SF Mono, Menlo.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var previewFont: Font {
        settings.terminalFontName.isEmpty
            ? .system(size: settings.terminalFontSize, design: .monospaced)
            : .custom(settings.terminalFontName, size: settings.terminalFontSize)
    }
}

private struct BehaviorPane: View {
    @EnvironmentObject private var settings: OrkSettings

    var body: some View {
        Form {
            Toggle("Start new sessions in an isolated worktree", isOn: $settings.defaultWorktree)
            Toggle("Notify when an agent finishes", isOn: $settings.notifyOnExit)
            Toggle("Confirm before closing a running session", isOn: $settings.confirmCloseRunning)
            Divider()
            Toggle("Privacy mode", isOn: $settings.privacyMode)
            Text("Shows only the current project's organization in the sidebar, menu bar and notch, and silences the notch event ticker. Flip it on before recording or presenting client work.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Divider()
            Toggle("Freeze idle sessions", isOn: $settings.freezeEnabled)
            Stepper(value: $settings.freezeMinutes, in: 1...60) {
                Text("Freeze after \(settings.freezeMinutes) min idle")
            }
            .disabled(!settings.freezeEnabled)
            Text("Idle sessions are suspended with SIGSTOP and stop burning CPU. Click a frozen card to wake it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
