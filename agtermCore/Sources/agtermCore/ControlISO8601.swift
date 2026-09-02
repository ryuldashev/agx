import Foundation

/// The one timestamp spelling the control API answers in: ISO 8601 with the LOCAL offset, so a script can
/// hand a `schedule.list` time straight back to `--at` and read a `restore.list` time without a timezone
/// guess. Owned here rather than per-node so the two cannot drift.
public enum ControlISO8601 {
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
