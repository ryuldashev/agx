import agtermCore
import Combine
import SwiftUI

/// One session's usage metrics, emitted by the Claude Code statusline to `~/.claude/agx-usage/<sid>.json`.
///
/// The statusline is the only place these numbers exist (Claude Code feeds each session its own JSON), so
/// it writes them out keyed by the AGX session id; this panel reads them back and joins them with the live
/// workspace tree. That join is what the per-session CC statusline can't do — the cross-session view.
struct SessionEmit: Decodable {
    let sid: String
    let model: String
    let ctx_pct: Double
    let ctx_size: Double
    let cost: Double
    let five_hour: Double
    let seven_day: Double
    let ts: Double
}

/// Polls the emit directory and republishes the parsed metrics keyed by uppercased session id. A file that
/// is missing, unreadable, or malformed is simply skipped — a broken emit never blanks the panel.
@MainActor
final class UsageReader: ObservableObject {
    @Published private(set) var emits: [String: SessionEmit] = [:]

    private var timer: Timer?
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/agx-usage", isDirectory: true)

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            if !emits.isEmpty { emits = [:] }
            return
        }
        let decoder = JSONDecoder()
        var next: [String: SessionEmit] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let emit = try? decoder.decode(SessionEmit.self, from: data) else { continue }
            next[emit.sid.uppercased()] = emit
        }
        if next != emits { emits = next }
    }
}

extension SessionEmit: Equatable {}

/// Cross-session usage strip for the sidebar footer: account rate-limit pools (5h / 7d), total live cost,
/// how many agent sessions are reporting, and a warning when any session has crossed the 200k
/// double-tariff line. Tapping it opens a per-session breakdown. Only sessions that are BOTH open (present
/// in the tree) AND reporting a fresh emit are shown, so a closed session's stale file never lingers here.
struct UsagePanel: View {
    @Bindable var store: AppStore
    let chromeText: Color

    @StateObject private var reader = UsageReader()
    @State private var showDetail = false

    private static let freshWindow: TimeInterval = 900

    /// (session, emit) for every open session with a fresh emit, newest-cost first is not needed — order by
    /// the tree. Closed sessions (no store entry) and stale emits drop out here.
    private var reporting: [(session: Session, emit: SessionEmit)] {
        let now = Date().timeIntervalSince1970
        return store.workspaces.flatMap(\.sessions).compactMap { session in
            guard let emit = reader.emits[session.id.uuidString.uppercased()],
                  now - emit.ts < Self.freshWindow else { return nil }
            return (session, emit)
        }
    }

    private var pools: (five: Int, seven: Int)? {
        guard let newest = reporting.map(\.emit).max(by: { $0.ts < $1.ts }) else { return nil }
        return (Int(newest.five_hour.rounded()), Int(newest.seven_day.rounded()))
    }

    private var totalCost: Double { reporting.reduce(0) { $0 + $1.emit.cost } }

    private func usedK(_ emit: SessionEmit) -> Int { Int(emit.ctx_size * emit.ctx_pct / 100 / 1000) }

    private var anyOverBudget: Bool { reporting.contains { usedK($0.emit) >= 200 } }

    var body: some View {
        Button { showDetail.toggle() } label: { strip }
            .buttonStyle(.plain)
            .popover(isPresented: $showDetail, arrowEdge: .top) { detail }
            .onAppear { reader.start() }
            .onDisappear { reader.stop() }
            .accessibilityIdentifier("usage-panel")
    }

    private var strip: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
                .imageScale(.small)
            if let pools {
                Text("5h \(pools.five)%").monospacedDigit()
                Text("·").opacity(0.35)
                Text("7d \(pools.seven)%").monospacedDigit()
                Text("·").opacity(0.35)
            }
            Text(String(format: "$%.2f", totalCost)).monospacedDigit()
            Spacer(minLength: 4)
            if anyOverBudget {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
            }
            Text("\(reporting.count)").monospacedDigit()
            Image(systemName: "rectangle.split.3x1")
                .imageScale(.small)
                .opacity(0.6)
        }
        .font(.system(size: 11))
        .foregroundStyle(chromeText.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help("Cross-session usage — tap for per-session detail")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AGX usage").font(.headline)
            if let pools {
                Text("account · 5h \(pools.five)% · 7d \(pools.seven)% of the subscription window")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if reporting.isEmpty {
                Text("No sessions reporting yet — each populates when its statusline next renders.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(reporting, id: \.session.id) { row in
                    let k = usedK(row.emit)
                    HStack(spacing: 8) {
                        Text(row.session.displayName).lineLimit(1)
                        Spacer(minLength: 12)
                        Text("\(row.emit.model)")
                            .foregroundStyle(.secondary)
                        Text("\(Int(row.emit.ctx_pct.rounded()))% (\(k)k)")
                            .monospacedDigit()
                            .foregroundStyle(k >= 200 ? .orange : .primary)
                        if k >= 200 { Text("⚠2x").foregroundStyle(.orange) }
                        Text(String(format: "$%.2f", row.emit.cost)).monospacedDigit()
                    }
                    .font(.system(size: 11))
                }
                Divider()
                Text(String(format: "total $%.2f · %d reporting", totalCost, reporting.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 400)
    }
}
