import Foundation

enum KeychainError: LocalizedError {
    case notFound
    case badFormat
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notFound: return "Claude Code credentials not found in Keychain. Run Claude Code and log in first."
        case .badFormat: return "Keychain credentials had an unexpected format."
        case .writeFailed: return "Couldn't save refreshed credentials to the Keychain."
        }
    }
}

/// The Claude Code OAuth credentials as stored in the Keychain.
/// `payload` is the full JSON so a write-back preserves every field
/// Claude Code stores (scopes, subscriptionType, ...), not just the ones
/// this app understands.
struct ClaudeCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var payload: [String: Any]

    var isFresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow > 300
    }
}

/// Reads and writes the Claude Code OAuth credentials in the login Keychain.
///
/// Uses the `security` CLI instead of SecItem* on purpose: this app is ad-hoc
/// signed, so its code identity changes on every rebuild. The Keychain
/// "Always Allow" grant attaches to Apple's stable `security` binary and
/// therefore survives rebuilds — the user is prompted exactly once.
enum KeychainToken {
    static let service = "Claude Code-credentials"

    static func accessToken() throws -> String {
        try read().accessToken
    }

    static func read() throws -> ClaudeCredentials {
        let raw = try run(["find-generic-password", "-s", service, "-w"])
        guard !raw.isEmpty else { throw KeychainError.notFound }
        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw KeychainError.badFormat }

        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expiresAt,
            payload: json
        )
    }

    /// Writes updated tokens back, preserving all other fields so Claude Code
    /// (which shares this entry) keeps working.
    static func write(_ credentials: ClaudeCredentials) throws {
        var payload = credentials.payload
        var oauth = payload["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = credentials.accessToken
        if let refreshToken = credentials.refreshToken { oauth["refreshToken"] = refreshToken }
        if let expiresAt = credentials.expiresAt {
            oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000)
        }
        payload["claudeAiOauth"] = oauth

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw KeychainError.writeFailed }

        let account = try currentAccount()
        do {
            _ = try run(["add-generic-password", "-U", "-a", account, "-s", service, "-w", json])
        } catch {
            throw KeychainError.writeFailed
        }
    }

    /// The account name on the existing entry (needed for add-generic-password).
    private static func currentAccount() throws -> String {
        let attrs = try run(["find-generic-password", "-s", service], captureStderr: true)
        for line in attrs.split(separator: "\n") {
            if let range = line.range(of: "\"acct\"<blob>=\"") {
                let rest = line[range.upperBound...]
                if let end = rest.firstIndex(of: "\"") { return String(rest[..<end]) }
            }
        }
        return NSUserName()
    }

    @discardableResult
    private static func run(_ arguments: [String], captureStderr: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw KeychainError.notFound }
        // Note: some subcommands (add-generic-password) print nothing on
        // success — empty output is not an error here.
        let data = captureStderr ? outData + errData : outData
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
