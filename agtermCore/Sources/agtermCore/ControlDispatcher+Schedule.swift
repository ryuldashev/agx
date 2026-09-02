import Foundation

extension ControlDispatcher {
    /// Validates `schedule.*` host-free: the time grammar, the brief, and the mutually exclusive
    /// destinations. Workspace and agent references need the store and settings, so they resolve app-side.
    func dispatchScheduleCommand(_ request: ControlRequest, now: Date = Date()) -> ControlResponse {
        switch request.cmd {
        case .scheduleAdd:
            return dispatchScheduleAdd(request, now: now)
        case .scheduleList:
            return actions.scheduleList()
        case .scheduleCancel:
            guard let target = request.target.trimmedOrNilValue else {
                return ControlResponse(ok: false, error: "schedule.cancel requires a schedule id")
            }
            return actions.scheduleCancel(target)
        case .scheduleRun:
            guard let target = request.target.trimmedOrNilValue else {
                return ControlResponse(ok: false, error: "schedule.run requires a schedule id")
            }
            return actions.scheduleRun(target)
        default:
            preconditionFailure("dispatchScheduleCommand called for \(request.cmd.rawValue)")
        }
    }

    private func dispatchScheduleAdd(_ request: ControlRequest, now: Date) -> ControlResponse {
        let args = request.args
        guard let brief = args?.brief, !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ControlResponse(ok: false, error: "schedule.add requires a brief")
        }
        guard let raw = args?.at.trimmedOrNilValue else {
            return ControlResponse(ok: false, error: "schedule.add requires --at (\(ScheduleTime.acceptedForms))")
        }
        guard let fireAt = ScheduleTime.parse(raw, now: now) else {
            return ControlResponse(ok: false, error: "invalid time: \(raw) (\(ScheduleTime.acceptedForms))")
        }
        guard fireAt > now else {
            return ControlResponse(ok: false, error: "time is in the past: \(raw)")
        }
        if args?.workspace != nil, args?.workspaceName != nil {
            return ControlResponse(ok: false, error: "use either --workspace or --workspace-name, not both")
        }
        if args?.agent != nil, args?.command != nil {
            return ControlResponse(ok: false, error: "use either --agent or --command, not both")
        }
        if let name = args?.name, containsControlCharacters(name) {
            return ControlResponse(ok: false, error: "name must not contain control characters")
        }
        return actions.scheduleAdd(ControlScheduleAddOptions(
            window: args?.window, fireAt: fireAt, brief: brief, name: args?.name.trimmedOrNilValue,
            workspace: args?.workspace.trimmedOrNilValue, workspaceName: args?.workspaceName.trimmedOrNilValue,
            cwd: args?.cwd.trimmedOrNilValue, agent: args?.agent.trimmedOrNilValue,
            command: args?.command.trimmedOrNilValue, foreground: args?.noSelect != true))
    }
}
