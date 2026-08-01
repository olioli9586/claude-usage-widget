import Foundation

/// Persists the latest snapshot to Application Support so other consumers
/// (e.g. a future WidgetKit extension reading from an App Group) can share it.
enum SnapshotStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

    static func write(_ snapshot: UsageSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try ISO8601.encoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SnapshotStore write failed: \(error)")
        }
    }

    static func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? ISO8601.decoder().decode(UsageSnapshot.self, from: data)
    }
}
