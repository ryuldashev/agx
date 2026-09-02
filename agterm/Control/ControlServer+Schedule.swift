import Foundation
import agtermCore

/// App-side host for `schedule.*`. The dispatcher parsed the time and required the brief; this layer
/// resolves the workspace against a live store and the agent against settings, then hands the finished
/// job to `SessionScheduler`, which owns the timer and the fire.
extension ControlServer {
    private var scheduler: SessionScheduler? { actions.scheduler }

    func scheduleAdd(_ options: ControlScheduleAddOptions) -> ControlResponse {
        guard let scheduler else { return ControlResponse(ok: false, error: "scheduler not started") }
        var launch = options.command
        if let reference = options.agent {
            guard let agent = agent(matching: reference) else {
                return ControlResponse(ok: false, error: "no such agent: \(reference)")
            }
            launch = agent.launchCommand
        }
        return resolver.resolvePlacementStore(options.window) { store in
            resolveScheduleWorkspace(options, in: store) { workspaceID, workspaceName in
                let item = ScheduledSession(fireAt: options.fireAt, brief: options.brief, name: options.name,
                                            windowID: self.library.windowID(for: store), workspaceID: workspaceID,
                                            workspaceName: workspaceName, cwd: options.cwd, launch: launch,
                                            foreground: options.foreground)
                guard scheduler.add(item) else {
                    return ControlResponse(ok: false, error: "could not persist the scheduled session")
                }
                return ControlResponse(ok: true, result: ControlResult(id: item.id.uuidString,
                                                                       scheduled: [ControlScheduledNode.project(item, now: Date())]))
            }
        }
    }

    /// A workspace named at add time is looked up now so a typo fails here, not silently at fire time; an
    /// absent one is stored by name and created when the job fires. An id must exist.
    private func resolveScheduleWorkspace(_ options: ControlScheduleAddOptions, in store: AppStore,
                                          _ body: (UUID?, String?) -> ControlResponse) -> ControlResponse {
        if let name = options.workspaceName {
            let existing = store.workspace(named: name)
            return body(existing?.id, name)
        }
        let target = options.workspace ?? "active"
        return resolver.resolve(target, candidates: store.workspaces.map(\.id),
                                active: store.currentWorkspaceID, noun: "workspace") { workspaceID in
            body(workspaceID, store.workspaces.first { $0.id == workspaceID }?.name)
        }
    }

    func scheduleList() -> ControlResponse {
        guard let scheduler else { return ControlResponse(ok: false, error: "scheduler not started") }
        return ControlResponse(ok: true, result: ControlResult(scheduled: scheduler.nodes()))
    }

    func scheduleCancel(_ target: String) -> ControlResponse {
        resolveSchedule(target) { scheduler, id in
            guard scheduler.cancel(id) else { return ControlResponse(ok: false, error: "no such scheduled session") }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString, affected: 1))
        }
    }

    func scheduleRun(_ target: String) -> ControlResponse {
        resolveSchedule(target) { scheduler, id in
            guard let session = scheduler.run(id) else {
                return ControlResponse(ok: false, error: "could not open the scheduled session (no open window?)")
            }
            return ControlResponse(ok: true, result: ControlResult(id: session.uuidString))
        }
    }

    private func resolveSchedule(_ target: String, _ body: (SessionScheduler, UUID) -> ControlResponse) -> ControlResponse {
        guard let scheduler else { return ControlResponse(ok: false, error: "scheduler not started") }
        return resolver.resolve(target, candidates: scheduler.items.map(\.id), active: nil, noun: "scheduled session") { id in
            body(scheduler, id)
        }
    }

    func scheduledNodes() -> [ControlScheduledNode]? {
        guard let nodes = scheduler?.nodes(), !nodes.isEmpty else { return nil }
        return nodes
    }
}
