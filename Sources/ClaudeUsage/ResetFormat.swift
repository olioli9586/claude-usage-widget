import Foundation

/// Text for the reset countdowns in the menu. Kept free of SwiftUI so it can
/// be unit tested with a fixed clock, locale and time zone.
enum ResetFormat {
    /// Time left until `date`: "3d 04h", "2h 14m" or "4m 09s". Never negative.
    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let d = seconds / 86_400, h = (seconds % 86_400) / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if d > 0 { return String(format: "%dd %02dh", d, h) }
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }

    /// Weekday and time of the reset, e.g. "Mon 09:00" (format follows the locale).
    /// Rounded to the nearest minute: the API reports times like 08:59:59.9,
    /// which should read as 09:00, not 08:59.
    static func weekdayTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
            .weekday(.abbreviated).hour().minute()
        return rounded.formatted(style)
    }

    /// "Session resets in 2h 14m", or nil once there is no future reset.
    static func sessionCountdown(resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        return "Session resets in \(remaining(until: resetsAt, now: now))"
    }

    /// "Weekly resets Mon 09:00 · 3d 04h", or nil once there is no future reset.
    static func weeklyReset(resetsAt: Date?, now: Date,
                            locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let when = weekdayTime(resetsAt, locale: locale, timeZone: timeZone)
        return "Weekly resets \(when) · \(remaining(until: resetsAt, now: now))"
    }
}
