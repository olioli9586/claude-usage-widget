import Foundation

/// One rate-limit window as reported by the usage API.
struct UsageWindow: Codable, Equatable {
    var utilization: Double        // percent, 0–100
    var resetsAt: Date?
}

/// The on-disk contract shared with the future WidgetKit extension (Phase 2).
struct UsageSnapshot: Codable, Equatable {
    enum Status: String, Codable {
        case ok
        case rateLimited
        case authNeeded
        case error
    }

    var fetchedAt: Date
    var status: Status
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    static let placeholder = UsageSnapshot(fetchedAt: .distantPast, status: .error, fiveHour: nil, sevenDay: nil)

    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 10 * 60
    }
}

enum ISO8601 {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: s) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date: \(s)"))
            }
            return date
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
