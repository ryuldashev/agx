import Darwin
import Foundation
import OSLog
import agtermCore

/// Platform half of durable panes (ADR 0001): the bundled abduco, the socket under the state directory,
/// the pid file the wrapper writes, the server kill on discard, and the program's argv for `tree`.
enum DurableSpawn {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "DurableSpawn")

    /// The bundled abduco, nil when the resource is missing — spawns then run unwrapped, logged once.
    static let abducoPath: String? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("abduco/abduco"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url.path
    }()

    /// The plan `makeSurface` spawns: `base` wrapped in the abduco client when the session qualifies, marking
    /// `session.durable`; `base` untouched otherwise. A wrap that cannot happen (no binary, a state dir too
    /// long for `sun_path`) degrades to today's spawn rather than a dead pane.
    @MainActor
    static func plan(_ base: CommandRestore.RestorePlan, session: Session,
                     stateDirectory: String) -> CommandRestore.RestorePlan {
        let socket = DurablePane.socketPath(stateDirectory: stateDirectory, sessionID: session.id)
        let serverExists = FileManager.default.fileExists(atPath: socket)
        guard let line = DurablePane.programLine(base, serverExists: serverExists) else { return base }
        guard DurablePane.shouldWrap(settingOn: GhosttyApp.shared.durablePanes, requested: session.durableRequested,
                                     serverExists: serverExists, line: line) else { return base }
        guard let abduco = abducoPath else {
            logger.error("abduco missing from the bundle; spawning unwrapped")
            return base
        }
        guard DurablePane.fits(socket: socket) else {
            logger.error("state directory too long for a session socket; spawning unwrapped")
            return base
        }
        try? FileManager.default.createDirectory(atPath: (socket as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        session.durable = true
        return CommandRestore.RestorePlan(command: DurablePane.command(abduco: abduco, socket: socket, line: line),
                                          initialInput: nil)
    }

    /// The program's live argv for `tree.foreground`: the pane's own foreground is the abduco client, so
    /// the pid file's process is read instead — trusted only while its parent is this socket's server, which
    /// a pid reused after a reboot fails.
    @MainActor
    static func foreground(session: Session, stateDirectory: String, shellBasename: String?) -> [String]? {
        guard let live = live(sessionID: session.id, stateDirectory: stateDirectory),
              let argv = ForegroundProcess.procArgs(pid: live.program) else { return nil }
        return ForegroundProcess.usable(argv, shellBasename: shellBasename)
    }

    /// A session closed for good: SIGTERM the server (its handler exits, the atexit unlinks the socket, the
    /// closing pty master SIGHUPs the program) and drop the pid file. No-op when nothing of it remains, so
    /// it is safe to call for every discarded session, durable or not.
    @MainActor
    static func discard(session: Session, stateDirectory: String) {
        let socket = DurablePane.socketPath(stateDirectory: stateDirectory, sessionID: session.id)
        if let live = live(sessionID: session.id, stateDirectory: stateDirectory) {
            kill(live.server, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: DurablePane.pidFilePath(socket: socket))
    }

    /// The program and server pids behind a session's pid file, nil unless both are alive and the parent's
    /// argv names this socket (the abduco command line carries it).
    private static func live(sessionID: UUID, stateDirectory: String) -> (program: pid_t, server: pid_t)? {
        let socket = DurablePane.socketPath(stateDirectory: stateDirectory, sessionID: sessionID)
        guard let text = try? String(contentsOfFile: DurablePane.pidFilePath(socket: socket), encoding: .utf8),
              let program = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              program > 1, let server = parentPid(of: program), server > 1,
              ForegroundProcess.procArgs(pid: server)?.contains(socket) == true else { return nil }
        return (program, server)
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
