import Foundation
import Testing
@testable import ClaudeUsage

@Suite struct UsageAPIClientTests {
    private let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test func okReturnsBody() throws {
        let body = Data(#"{"five_hour":null}"#.utf8)
        #expect(try UsageAPIClient.validate(data: body, response: response(200)) == body)
    }

    @Test(arguments: [401, 403])
    func authFailuresAreUnauthorized(_ status: Int) {
        #expect {
            try UsageAPIClient.validate(data: Data(), response: response(status))
        } throws: { error in
            if case UsageAPIError.unauthorized = error { return true }
            return false
        }
    }

    @Test func rateLimitCarriesRetryAfter() {
        #expect {
            try UsageAPIClient.validate(data: Data(), response: response(429, headers: ["Retry-After": "120"]))
        } throws: { error in
            if case UsageAPIError.rateLimited(let retryAfter) = error { return retryAfter == 120 }
            return false
        }
    }

    @Test func otherStatusesAreHTTPErrors() {
        #expect {
            try UsageAPIClient.validate(data: Data(), response: response(503))
        } throws: { error in
            if case UsageAPIError.http(503) = error { return true }
            return false
        }
    }

    /// Previously a force cast: a non-HTTP response crashed the app.
    @Test func nonHTTPResponseIsAnErrorNotACrash() {
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect {
            try UsageAPIClient.validate(data: Data(), response: plain)
        } throws: { error in
            if case UsageAPIError.http(0) = error { return true }
            return false
        }
    }

    @Test(arguments: [
        ("120", 120.0), (" 30 ", 30.0), ("0", 0.0), ("1.5", 1.5),
    ] as [(String, TimeInterval)])
    func retryAfterAcceptsDeltaSeconds(_ header: String, _ expected: TimeInterval) {
        #expect(UsageAPIClient.retryAfter(header) == expected)
    }

    @Test(arguments: [nil, "", "soon", "-5", "inf", "nan", "Wed, 21 Oct 2025 07:28:00 GMT"] as [String?])
    func retryAfterRejectsUnusableValues(_ header: String?) {
        #expect(UsageAPIClient.retryAfter(header) == nil)
    }
}

@Suite struct PollerDelayTests {
    @Test func normalPollingIsBaseIntervalPlusJitter() {
        #expect(Poller.delay(consecutiveRateLimits: 0, retryAfter: nil, jitter: 7) == 187)
        #expect(Poller.delay(consecutiveRateLimits: 0, retryAfter: 9999, jitter: -15) == 165)
    }

    @Test func backoffDoublesAndCapsAtThirtyMinutes() {
        let delays = (1...8).map { Poller.delay(consecutiveRateLimits: $0, retryAfter: nil) }
        #expect(delays == [60, 120, 240, 480, 960, 1800, 1800, 1800])
    }

    @Test func longerRetryAfterWinsButIsBounded() {
        #expect(Poller.delay(consecutiveRateLimits: 1, retryAfter: 30) == 60)
        #expect(Poller.delay(consecutiveRateLimits: 1, retryAfter: 600) == 600)
        #expect(Poller.delay(consecutiveRateLimits: 1, retryAfter: 86_400 * 365) == Poller.maxRetryAfter)
    }

    @Test func delayIsAlwaysAValidSleepDuration() {
        for n in [1, 10, 1000, Int.max / 2] {
            let d = Poller.delay(consecutiveRateLimits: n, retryAfter: .greatestFiniteMagnitude)
            #expect(d.isFinite && d <= Poller.maxRetryAfter)
            _ = Duration.seconds(d)
        }
    }
}
