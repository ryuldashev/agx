import agtermCore
import SwiftUI

/// Settings ▸ Agents: the list of local agent CLIs the user has connected, and the ones found on this
/// Mac that they have not. A connected agent is just a name plus a shell line, so anything runnable
/// qualifies — the detected list is a shortcut, never a gate.
///
/// The list is global (it lives in `settings.json`); WHERE an agent runs is per workspace, pinned in the
/// sidebar's Workspace Defaults… sheet, which picks from exactly these rows.
struct AgentsSettingsView: View {
    let model: SettingsModel

    /// Detected once per Settings open: probing `PATH` on every keystroke would stat the disk while typing
    /// a command, and an agent installed mid-session is picked up by the explicit Rescan.
    @State private var detected: [KnownAgent] = []

    var body: some View {
        Form {
            Section("Connected") {
                if model.settings.agents?.isEmpty ?? true {
                    Text("No agents connected. Add one below, then pin it to a workspace with the sidebar's Workspace Defaults….")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(agents) { agent in
                    AgentRow(model: model, agent: agent)
                }
                Button("Add Custom Agent…") { model.addAgent(name: "New agent", command: "") }
                    .accessibilityIdentifier("settings-agents-add")
            }

            Section("Found on This Mac") {
                if available.isEmpty {
                    Text(detected.isEmpty
                        ? "No known agent CLIs found on PATH."
                        : "Every agent found on this Mac is already connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(available) { known in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(known.name)
                            Text(known.binary)
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { model.addAgent(name: known.name, command: known.command) }
                    }
                }
                HStack {
                    SettingHint("An agent runs as the session's own process, so closing it closes the tab.")
                    Spacer()
                    Button("Rescan") { detected = AgentCatalog.detectInstalled() }
                        .accessibilityIdentifier("settings-agents-rescan")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { detected = AgentCatalog.detectInstalled() }
    }

    private var agents: [AgentDefinition] { model.settings.agents ?? [] }

    /// Detected agents not already connected — matched on the launch line, so re-adding `claude` after
    /// renaming its row to "Work Claude" is still recognized as connected.
    private var available: [KnownAgent] {
        let commands = Set(agents.map { $0.command.trimmingCharacters(in: .whitespaces) })
        return detected.filter { !commands.contains($0.command) }
    }
}

/// One connected agent: an editable display name, an editable launch line, and Remove. Both fields
/// commit on every change — `SettingsModel` writes `settings.json`, which is cheap and keeps the
/// workspace picker in step without a Save button. It holds the model rather than callbacks so the
/// bindings stay main-actor-isolated (a captured closure crossing into `Binding` is not `Sendable`).
private struct AgentRow: View {
    let model: SettingsModel
    let agent: AgentDefinition

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            TextField("Command", text: command, prompt: Text("claude"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12).monospaced())
            Button(role: .destructive) { model.removeAgent(id: agent.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove this agent")
        }
    }

    private var name: Binding<String> {
        Binding(get: { agent.name }, set: { model.updateAgent(id: agent.id, name: $0, command: nil) })
    }

    private var command: Binding<String> {
        Binding(get: { agent.command }, set: { model.updateAgent(id: agent.id, name: nil, command: $0) })
    }
}
