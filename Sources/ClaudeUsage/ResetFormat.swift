import Foundation

/// Text for the reset countdowns in the menu. Kept free of SwiftUI so it can
/// be unit tested with a fixed clock.
enum ResetFormat {
    /// Time left until `date`: "3d 04h", "2h 14m" or "4m 09s". Never negative.
    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let d = seconds / 86_400, h = (seconds % 86_400) / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if d > 0 { return String(format: "%dd %02dh", d, h) }
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }

    /// "Session resets in 2h 14m", or nil once there is no future reset.
    static func sessionCountdown(resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        return "Session resets in \(remaining(until: resetsAt, now: now))"
    }
}
