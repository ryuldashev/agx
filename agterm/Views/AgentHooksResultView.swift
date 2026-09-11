import agtermCore
import SwiftUI

/// The result of Help ▸ Install Agent Status Hooks: one row per agent with a status mark and a plain
/// one-liner — no paths, no generated blocks (an NSAlert grew past the screen with those, #430). The
/// shell integration gets the last row. `Open Docs` appears only when a row needs a hand merge.
struct AgentHooksResultView: View {
    let rows: [AgentHooksInstaller.Row]
    let docs: URL?
    let onOpenDocs: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rows.contains { $0.result.isWarning } ? "Hooks installed, with a warning" : "Agent status hooks installed")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    AgentHooksResultRow(row: row)
                    if index < rows.count - 1 { Divider().padding(.leading, 44) }
                }
                Divider().padding(.leading, 44)
                shellRow
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack {
                Spacer()
                if docs != nil {
                    Button("Open Docs", action: onOpenDocs)
                }
                Button("OK", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 440)
    }

    private var shellRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .darkGray).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Shell integration")
                Text("Added to zsh, bash and fish. Open a new terminal for it to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct AgentHooksResultRow: View {
    let row: AgentHooksInstaller.Row

    var body: some View {
        HStack(spacing: 12) {
            AgentTile(profile: row.profile)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.profile.name)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            mark
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(row.result == .notInstalled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var mark: some View {
        switch row.result {
        case .merged, .unchanged:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notInstalled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
