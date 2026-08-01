import Foundation

enum KeychainError: LocalizedError {
    case notFound
    case badFormat

    var errorDescription: String? {
        switch self {
        case .notFound: return "Claude Code credentials not found in Keychain. Run Claude Code and log in first."
        case .badFormat: return "Keychain credentials had an unexpected format."
        }
    }
}

/// Reads the Claude Code OAuth access token from the login Keychain.
///
/// Uses the `security` CLI instead of SecItemCopyMatching on purpose: this app
/// is ad-hoc signed, so its code identity changes on every rebuild. The
/// Keychain "Always Allow" grant attaches to Apple's stable `security` binary
/// and therefore survives rebuilds — the user is prompted exactly once.
enum KeychainToken {
    static let service = "Claude Code-credentials"

    static func accessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw KeychainError.notFound }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { throw KeychainError.notFound }

        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw KeychainError.badFormat }

        return token
    }
}
