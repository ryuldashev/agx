import agtermCore
import SwiftUI

/// The Welcome panel: a setup checklist read from the system, the first moves that show what agx is for,
/// and the discovery map. One panel, no wizard — every row is done or not, and its button does the one
/// thing that flips it. Same rows-in-a-card shape as the hooks result window.
struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let onClose: () -> Void

    static let width: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            setup
            firstMoves
            discoveries
            footer
        }
        .padding(20)
        .frame(width: Self.width)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome to \(Brand.productName)")
                .font(.title2.weight(.semibold))
            Text("A terminal for running many coding agents at once: each one in a named session that shows "
                 + "whether it is working, done or waiting for you, and can drive this window itself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(model.setupComplete ? "Setup complete" : "Set up",
                         trailing: model.setupComplete ? nil : "\(doneCount) of \(requiredCount)")
            card {
                ForEach(Array(OnboardingSetup.Step.allCases.enumerated()), id: \.element) { index, step in
                    SetupRow(step: step, state: model.states[step] ?? .unknown) { model.perform(step) }
                    if index < OnboardingSetup.Step.allCases.count - 1 { Divider().padding(.leading, 48) }
                }
            }
        }
    }

    private var requiredCount: Int {
        OnboardingSetup.Step.allCases.filter { step in
            if case .optional = model.states[step] { return false }
            return true
        }.count
    }

    private var doneCount: Int {
        OnboardingSetup.Step.allCases.filter { model.states[$0]?.isDone == true }.count
    }

    // MARK: - First moves

    private var firstMoves: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("First moves", trailing: nil)
            card {
                ForEach(Array(Discovery.firstMoves.enumerated()), id: \.element) { index, discovery in
                    DiscoveryRow(discovery: discovery, done: model.discovered.contains(discovery))
                    if index < Discovery.firstMoves.count - 1 { Divider().padding(.leading, 48) }
                }
            }
        }
    }

    // MARK: - Discoveries

    private var discoveries: some View {
        let total = Discovery.allCases.count
        let count = model.discovered.count
        let undiscovered = Discovery.allCases.filter { !model.discovered.contains($0) && !Discovery.firstMoves.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Discovered \(count) of \(total)", trailing: nil)
            ProgressView(value: Double(count), total: Double(total))
                .progressViewStyle(.linear)
                .accessibilityIdentifier("welcome-discovered")
            if !undiscovered.isEmpty {
                Text("Still to try: " + undiscovered.map { $0.title.lowercased() }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if count == total {
                Text("Everything on the map, once. Reset it to show agx to someone else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Guide") {
                if let url = WelcomeModel.guideURL() { NSWorkspace.shared.open(url) }
            }
            Button("Reset Discoveries") { model.resetDiscoveries() }
                .disabled(model.discovered.isEmpty)
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome-close")
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SetupRow: View {
    let step: OnboardingSetup.Step
    let state: OnboardingSetup.State
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 1) {
                Text(OnboardingSetup.title(step))
                Text(state.detail ?? OnboardingSetup.purpose(step))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            mark
            if !state.isDone {
                Button(OnboardingSetup.action(step), action: action)
                    .controlSize(.small)
                    .accessibilityIdentifier("welcome-\(step.rawValue)-action")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome-\(step.rawValue)")
    }

    private var tile: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color(nsColor: .darkGray).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch step {
        case .notifications: return "bell"
        case .toolPermissions: return "lock.shield"
        case .cli: return "terminal"
        case .hooks: return "link"
        case .skill: return "book"
        case .agent: return "sparkles"
        }
    }

    @ViewBuilder private var mark: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .optional:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .unknown:
            ProgressView().controlSize(.small)
        }
    }
}

private struct DiscoveryRow: View {
    let discovery: Discovery
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(Discovery.firstMoves.firstIndex(of: discovery).map { $0 + 1 } ?? 0)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background((done ? Color.green : Color(nsColor: .darkGray)).gradient,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(discovery.title)
                Text(discovery.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome-move-\(discovery.rawValue)")
    }
}
