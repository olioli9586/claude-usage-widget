import Foundation
import Testing
@testable import ClaudeUsage

@Suite struct UsageParsingTests {
    let client = UsageAPIClient()

    private func date(_ s: String) -> Date { ISO8601.date(from: s)! }

    @Test func parsesBothWindowsWithResetTimes() throws {
        let json = """
        {
          "five_hour": {"utilization": 16.0, "resets_at": "2025-09-01T19:00:00.542137+00:00"},
          "seven_day": {"utilization": 64.5, "resets_at": "2025-09-05T09:00:00+00:00"},
          "seven_day_opus": {"utilization": 3.0, "resets_at": null}
        }
        """
        let (five, seven) = try client.parse(Data(json.utf8))
        #expect(five == UsageWindow(utilization: 16, resetsAt: date("2025-09-01T19:00:00.542Z")))
        #expect(seven?.utilization == 64.5)
        #expect(seven?.resetsAt == date("2025-09-05T09:00:00Z"))
    }

    @Test func nullResetMeansNoActiveWindow() throws {
        let json = #"{"five_hour": {"utilization": 0, "resets_at": null}, "seven_day": {"utilization": 12}}"#
        let (five, seven) = try client.parse(Data(json.utf8))
        #expect(five == UsageWindow(utilization: 0, resetsAt: nil))
        #expect(seven == UsageWindow(utilization: 12, resetsAt: nil))
    }

    @Test func missingOrNullWindowsAreNil() throws {
        let json = #"{"five_hour": null, "seven_day": {"utilization": null, "resets_at": "2025-09-05T09:00:00Z"}}"#
        let (five, seven) = try client.parse(Data(json.utf8))
        #expect(five == nil)
        #expect(seven == nil)
        let empty = try client.parse(Data("{}".utf8))
        #expect(empty.fiveHour == nil && empty.sevenDay == nil)
    }

    @Test func unrecognizedDateIsAnError() {
        let json = #"{"seven_day": {"utilization": 1, "resets_at": "next tuesday"}}"#
        #expect(throws: DecodingError.self) { try client.parse(Data(json.utf8)) }
    }

    @Test(arguments: [
        "2025-09-05T09:00:00Z",
        "2025-09-05T09:00:00+00:00",
        "2025-09-05T11:00:00+02:00",
        "2025-09-05T09:00:00.000Z",
        "2025-09-05T09:00:00.000000+00:00",
    ])
    func iso8601AcceptsApiVariants(_ s: String) {
        #expect(ISO8601.date(from: s) == Date(timeIntervalSince1970: 1_757_062_800))
    }
}

@Suite struct SnapshotCodingTests {
    @Test func roundTripsThroughTheOnDiskFormat() throws {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
            status: .rateLimited,
            fiveHour: UsageWindow(utilization: 16, resetsAt: Date(timeIntervalSince1970: 1_757_010_000)),
            sevenDay: UsageWindow(utilization: 64.5, resetsAt: Date(timeIntervalSince1970: 1_757_062_800))
        )
        let data = try ISO8601.encoder().encode(snapshot)
        #expect(try ISO8601.decoder().decode(UsageSnapshot.self, from: data) == snapshot)
    }

    @Test func placeholderIsStale() {
        #expect(UsageSnapshot.placeholder.isStale)
        var fresh = UsageSnapshot.placeholder
        fresh.fetchedAt = Date()
        #expect(!fresh.isStale)
    }
}
