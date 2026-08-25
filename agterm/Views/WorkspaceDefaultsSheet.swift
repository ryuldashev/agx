import agtermCore
import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// The sheet behind the sidebar's "Workspace Defaults…": pins the directory and the agent every new
/// session in that workspace starts with. Both are optional and independent — pinning only a directory
/// opens plain shells there, pinning only an agent runs it wherever the global setting lands.
///
/// Presented as a real window sheet rather than a Settings pane because the value is per workspace and
/// the row you right-clicked is the context; Settings ▸ Agents owns the agent LIST this picks from.
struct WorkspaceDefaultsSheetView: View {
    let workspaceName: String
    let agents: [AgentDefinition]
    /// Applied on Save; the sheet closes either way through `dismiss`.
    let onSave: (WorkspaceDefaults) -> Void
    let dismiss: () -> Void

    @State private var directory: String
    @State private var agentID: UUID?
    /// The background image path as typed/picked; empty = no background for this workspace.
    @State private var backgroundPath: String
    /// `background-image-opacity`. A photo at full strength swallows the text, so a freshly picked image
    /// starts dimmed (`Self.defaultBackgroundOpacity`) rather than at ghostty's 1.0.
    @State private var backgroundOpacity: Double
    private let backgroundFit: BackgroundWatermark.Fit

    init(workspaceName: String, defaults: WorkspaceDefaults, agents: [AgentDefinition],
         onSave: @escaping (WorkspaceDefaults) -> Void, dismiss: @escaping () -> Void) {
        self.workspaceName = workspaceName
        self.agents = agents
        self.onSave = onSave
        self.dismiss = dismiss
        // seeded once: the sheet edits a copy and writes it back on Save, so Cancel is a true no-op.
        _directory = State(initialValue: defaults.cwd ?? "")
        // a pinned agent that has since been deleted resolves to "None", matching what a new session does.
        _agentID = State(initialValue: agents.contains { $0.id == defaults.agentID } ? defaults.agentID : nil)
        _backgroundPath = State(initialValue: defaults.background?.imagePath ?? "")
        _backgroundOpacity = State(initialValue: defaults.background?.opacity ?? Self.defaultBackgroundOpacity)
        // the sheet edits the image and its strength only; a fit set from the control API survives a Save.
        backgroundFit = defaults.background?.fit ?? .cover
    }

    /// What a newly picked image starts at: dim enough that the terminal text stays the thing you read.
    private static let defaultBackgroundOpacity = 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Defaults for \u{201C}\(workspaceName)\u{201D}")
                .font(.headline)
            // A Grid, not a grouped Form: a grouped Form is scroll-backed and reports no ideal height,
            // so inside the sheet's hosting controller it collapsed to nothing and the fields vanished.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Directory:")
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 8) {
                        TextField("Directory", text: $directory, prompt: Text("Default new-session directory"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityIdentifier("workspace-defaults-dir")
                        Button("Choose\u{2026}") { chooseDirectory() }
                            .accessibilityIdentifier("workspace-defaults-choose")
                    }
                }
                GridRow {
                    Text("Agent:")
                        .gridColumnAlignment(.trailing)
                    Picker("Agent", selection: $agentID) {
                        Text("None (plain shell)").tag(UUID?.none)
                        ForEach(agents) { agent in
                            Text(agent.name).tag(UUID?.some(agent.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("workspace-defaults-agent")
                }
                GridRow {
                    Text("Background:")
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 8) {
                        TextField("Background", text: $backgroundPath,
                                  prompt: Text("Image behind the terminal (PNG or JPEG)"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityIdentifier("workspace-defaults-background")
                        Button("Choose\u{2026}") { chooseBackground() }
                            .accessibilityIdentifier("workspace-defaults-background-choose")
                        Button("Clear") { backgroundPath = "" }
                            .disabled(backgroundPath.isEmpty)
                            .accessibilityIdentifier("workspace-defaults-background-clear")
                    }
                }
                if !backgroundPath.isEmpty {
                    GridRow {
                        Text("Strength:")
                            .gridColumnAlignment(.trailing)
                        HStack(spacing: 8) {
                            Slider(value: $backgroundOpacity, in: 0.05...1)
                                .accessibilityIdentifier("workspace-defaults-background-opacity")
                            Text("\(Int((backgroundOpacity * 100).rounded()))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(WorkspaceDefaults(cwd: directory.trimmingCharacters(in: .whitespacesAndNewlines),
                                             agentID: agentID, background: editedBackground))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("workspace-defaults-save")
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Points at Settings ▸ Agents when there is nothing to pick — an empty picker is otherwise a dead end.
    private var footer: String {
        agents.isEmpty
            ? "New sessions here open in this directory. Connect an agent in Settings ▸ Agents to run one automatically."
            : "New sessions here open in this directory and run the selected agent. A path may start with ~."
    }

    /// The edited background as a spec, nil when the path is blank. `.image` only — a workspace pins a
    /// picture, while `session.background`'s text/color modes stay a per-session thing.
    private var editedBackground: BackgroundWatermark? {
        let path = backgroundPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return BackgroundWatermark(kind: .image, imagePath: NSString(string: path).expandingTildeInPath,
                                   opacity: backgroundOpacity, fit: backgroundFit)
    }

    private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.prompt = "Choose"
        panel.message = "Choose the background image for new sessions in this workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundPath = url.path
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the default directory for new sessions in this workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory = url.path
    }
}

/// Presents `WorkspaceDefaultsSheetView` as a window sheet. Kept separate from the view so the AppKit
/// sidebar (an `NSOutlineView` delegate, not SwiftUI) can raise it from a menu action.
@MainActor
enum WorkspaceDefaultsSheet {
    /// Shows the sheet over `window`, calling `onSave` with the edited defaults. Falls back to a modal
    /// window when the sidebar has no window (a detached test host), so the action is never a silent no-op.
    static func present(over window: NSWindow?, workspaceName: String, defaults: WorkspaceDefaults,
                        agents: [AgentDefinition], onSave: @escaping (WorkspaceDefaults) -> Void) {
        // a box, not a captured local: the view's `dismiss` closure needs the window the controller is
        // about to be put in, which does not exist yet when the view is built.
        let holder = SheetHolder()
        let view = WorkspaceDefaultsSheetView(workspaceName: workspaceName, defaults: defaults, agents: agents,
                                              onSave: onSave) { holder.close(host: window) }
        let controller = NSHostingController(rootView: view)
        let sheet = NSWindow(contentViewController: controller)
        sheet.styleMask = [.titled]
        holder.window = sheet
        guard let window else {
            NSApp.runModal(for: sheet)
            return
        }
        window.beginSheet(sheet)
    }

    /// Holds the sheet window so the view's dismiss closure can end it exactly once.
    @MainActor
    private final class SheetHolder {
        var window: NSWindow?

        func close(host: NSWindow?) {
            guard let window else { return }
            self.window = nil
            if let host {
                host.endSheet(window)
            } else {
                NSApp.stopModal()
                window.close()
            }
        }
    }
}
