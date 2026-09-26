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
