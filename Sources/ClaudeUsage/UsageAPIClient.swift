import Foundation

enum UsageAPIError: LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Token rejected (401) even after refresh. Open Claude Code once to log in again."
        case .rateLimited: return "Usage API is rate limiting (429). Backing off."
        case .http(let code): return "Usage API returned HTTP \(code)."
        }
    }
}

/// Client for the (undocumented) endpoint that powers Claude Code's /usage.
struct UsageAPIClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    // Without a claude-code User-Agent the request lands in an aggressively
    // rate-limited bucket that returns persistent 429s.
    static let userAgent = "claude-code/2.1.212 (external, cli)"

    struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: Date?
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    func fetch(token: String) async throws -> (fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        try parse(await fetchRaw(token: token))
    }

    func fetchRaw(token: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.validate(data: data, response: response)
    }

    /// Maps the HTTP status to the body or a typed error.
    static func validate(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw UsageAPIError.http(0) }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw UsageAPIError.unauthorized
        case 429:
            throw UsageAPIError.rateLimited(retryAfter: retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        default:
            throw UsageAPIError.http(http.statusCode)
        }
    }

    /// Retry-After in delta-seconds form. Rejects values that aren't a finite,
    /// non-negative number ("inf", "nan", "-5"): those would crash or
    /// misbehave when turned into a sleep Duration.
    static func retryAfter(_ header: String?) -> TimeInterval? {
        guard let header,
              let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0
        else { return nil }
        return seconds
    }

    func parse(_ data: Data) throws -> (fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        let decoded = try ISO8601.decoder().decode(Response.self, from: data)
        func window(_ w: Response.Window?) -> UsageWindow? {
            guard let w, let utilization = w.utilization else { return nil }
            return UsageWindow(utilization: utilization, resetsAt: w.resets_at)
        }
        return (window(decoded.five_hour), window(decoded.seven_day))
    }
}
