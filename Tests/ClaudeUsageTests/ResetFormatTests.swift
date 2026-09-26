import Foundation
import Testing
@testable import ClaudeUsage

@Suite struct ResetFormatTests {
    let now = Date(timeIntervalSince1970: 1_757_000_000)

    private func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    // seconds from now -> text (8_099 = 2h 14m 59s, 277_140 = 3d 04h 59m)
    static let remainingCases: [(TimeInterval, String)] = [
        (0, "0m 00s"),
        (9.9, "0m 09s"),
        (65, "1m 05s"),
        (3599, "59m 59s"),
        (3600, "1h 00m"),
        (8_099, "2h 14m"),
        (18_000, "5h 00m"),
        (86_399, "23h 59m"),
        (86_400, "1d 00h"),
        (277_140, "3d 04h"),
        (604_800, "7d 00h"),
    ]

    @Test(arguments: remainingCases)
    func remainingFormatsEachScale(_ seconds: TimeInterval, _ expected: String) {
        #expect(ResetFormat.remaining(until: after(seconds), now: now) == expected)
    }

    @Test func remainingNeverGoesNegative() {
        #expect(ResetFormat.remaining(until: after(-120), now: now) == "0m 00s")
    }

    @Test func sessionCountdownWhileWindowIsActive() {
        #expect(ResetFormat.sessionCountdown(resetsAt: after(2 * 3600 + 14 * 60), now: now)
                == "Session resets in 2h 14m")
    }

    @Test func sessionCountdownDisappearsOnceTheResetPasses() {
        #expect(ResetFormat.sessionCountdown(resetsAt: nil, now: now) == nil)
        #expect(ResetFormat.sessionCountdown(resetsAt: now, now: now) == nil)
        #expect(ResetFormat.sessionCountdown(resetsAt: after(-1), now: now) == nil)
    }
}

@Suite struct WeeklyResetFormatTests {
    let gb = Locale(identifier: "en_GB")
    let utc = TimeZone(identifier: "UTC")!
    // Mon 2025-09-01 12:00:00 UTC
    let now = ISO8601.date(from: "2025-09-01T12:00:00Z")!

    @Test func weekdayTimeUsesTheGivenLocaleAndTimeZone() {
        let reset = ISO8601.date(from: "2025-09-05T09:00:00Z")! // a Friday
        #expect(ResetFormat.weekdayTime(reset, locale: gb, timeZone: utc) == "Fri 09:00")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(ResetFormat.weekdayTime(reset, locale: gb, timeZone: tokyo) == "Fri 18:00")
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(ResetFormat.weekdayTime(reset, locale: gb, timeZone: la) == "Fri 02:00")
        let de = ResetFormat.weekdayTime(reset, locale: Locale(identifier: "de_DE"), timeZone: utc)
        #expect(de.contains("09:00") && de.hasPrefix("Fr"))
    }

    @Test func weekdayTimeRoundsToTheNearestMinute() {
        // The API's timestamps carry sub-second noise around the hour.
        let justBefore = ISO8601.date(from: "2025-09-05T08:59:59.943Z")!
        let justAfter = ISO8601.date(from: "2025-09-05T09:00:00.542Z")!
        #expect(ResetFormat.weekdayTime(justBefore, locale: gb, timeZone: utc) == "Fri 09:00")
        #expect(ResetFormat.weekdayTime(justAfter, locale: gb, timeZone: utc) == "Fri 09:00")
        // Rolls over the day boundary too.
        let midnight = ISO8601.date(from: "2025-09-05T23:59:45Z")!
        #expect(ResetFormat.weekdayTime(midnight, locale: gb, timeZone: utc) == "Sat 00:00")
    }

    @Test func weeklyResetShowsWhenAndHowLong() {
        let reset = ISO8601.date(from: "2025-09-05T09:00:00Z")!
        #expect(ResetFormat.weeklyReset(resetsAt: reset, now: now, locale: gb, timeZone: utc)
                == "Weekly resets Fri 09:00 · 3d 21h")
    }

    @Test func weeklyResetCountsDownToSecondsOnTheLastHour() {
        let reset = now.addingTimeInterval(125)
        #expect(ResetFormat.weeklyReset(resetsAt: reset, now: now, locale: gb, timeZone: utc)
                == "Weekly resets Mon 12:02 · 2m 05s")
    }

    @Test func weeklyResetIsHiddenWithoutAFutureReset() {
        #expect(ResetFormat.weeklyReset(resetsAt: nil, now: now) == nil)
        #expect(ResetFormat.weeklyReset(resetsAt: now, now: now) == nil)
        #expect(ResetFormat.weeklyReset(resetsAt: now.addingTimeInterval(-60), now: now) == nil)
    }

    /// End to end: the reset shown is the seven_day window's resets_at from
    /// the same usage response that feeds the Weekly bar.
    @Test func weeklyResetComesFromTheSevenDayWindow() throws {
        let json = """
        {"five_hour": {"utilization": 16, "resets_at": "2025-09-01T14:00:00Z"},
         "seven_day": {"utilization": 64, "resets_at": "2025-09-05T08:59:59.943000+00:00"}}
        """
        let (_, seven) = try UsageAPIClient().parse(Data(json.utf8))
        #expect(ResetFormat.weeklyReset(resetsAt: seven?.resetsAt, now: now, locale: gb, timeZone: utc)
                == "Weekly resets Fri 09:00 · 3d 20h")
    }
}
