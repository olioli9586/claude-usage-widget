import Foundation

enum TokenError: LocalizedError {
    case noRefreshToken
    case refreshRejected(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token in Keychain — open Claude Code once to log in."
        case .refreshRejected(let code):
            return "Login expired and auto-refresh was rejected (HTTP \(code)) — open Claude Code once to log in again."
        case .badResponse:
            return "Token refresh returned an unexpected response."
        }
    }
}

/// Keeps the OAuth access token valid without requiring Claude Code to run.
///
/// When the stored access token is (nearly) expired, exchanges the refresh
/// token at the same endpoint Claude Code uses and writes the new tokens back
/// to the shared Keychain entry — so Claude Code stays logged in too.
///
/// Race safety with Claude Code: refresh tokens may rotate, so we re-read the
/// Keychain immediately before refreshing (Claude Code may have refreshed
/// already) and single-flight our own refreshes.
@MainActor
final class TokenManager {
    // Note: platform.claude.com/v1/oauth/token exists too but aggressively
    // rate-limits third-party callers; this host accepts the claude-code flow.
    static let endpoint = URL(string: "https://api.anthropic.com/v1/oauth/token")!
    // Claude Code's public OAuth client ID (embedded in its CLI).
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private var refreshTask: Task<String, Error>?

    /// The stored token if still fresh, otherwise a refreshed one.
    func validAccessToken() async throws -> String {
        let credentials = try KeychainToken.read()
        if credentials.isFresh { return credentials.accessToken }
        return try await refresh()
    }

    /// Force a refresh — used when the API rejects a token that looked fresh.
    func refreshedToken() async throws -> String {
        try await refresh(force: true)
    }

    private func refresh(force: Bool = false) async throws -> String {
        if let task = refreshTask { return try await task.value }
        let task = Task<String, Error> { try await performRefresh(force: force) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(force: Bool) async throws -> String {
        // Re-read first: Claude Code may have refreshed since our caller read.
        var credentials = try KeychainToken.read()
        if !force, credentials.isFresh { return credentials.accessToken }
        guard let refreshToken = credentials.refreshToken else { throw TokenError.noRefreshToken }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(UsageAPIClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            NSLog("TokenManager: refresh rejected (HTTP \(status))")
            throw TokenError.refreshRejected(status)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw TokenError.badResponse
        }

        credentials.accessToken = token.access_token
        if let rotated = token.refresh_token { credentials.refreshToken = rotated }
        if let expiresIn = token.expires_in {
            credentials.expiresAt = Date().addingTimeInterval(expiresIn)
        }
        try KeychainToken.write(credentials)
        NSLog("TokenManager: token refreshed, expires \(credentials.expiresAt?.description ?? "?")")
        return token.access_token
    }
}
