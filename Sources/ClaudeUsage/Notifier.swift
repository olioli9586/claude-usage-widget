import Foundation
import UserNotifications

/// Fires "your 5h session refreshed" at the window's resets_at moment.
///
/// Primary path: UNCalendarNotificationTrigger (exact time, delivered on wake).
/// Fallback (when running unbundled or notification auth fails, e.g. some
/// ad-hoc-signed builds): an in-app timer that posts via osascript — the app
/// is always running, so this is nearly equivalent.
@MainActor
final class Notifier {
    private static let requestID = "five-hour-reset"
    private static let defaultsKey = "lastScheduledResetsAt"

    private var useUserNotifications = false
    private var fallbackTask: Task<Void, Never>?

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isBundled else {
            NSLog("Notifier: unbundled process, using osascript fallback")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.useUserNotifications = granted && error == nil
                if let error { NSLog("Notifier: auth failed (\(error)), using osascript fallback") }
            }
        }
    }

    func scheduleSessionReset(at resetsAt: Date?) {
        // A null resets_at means no active session; any previously scheduled
        // notification still corresponds to a real window expiry — leave it.
        guard let resetsAt, resetsAt > Date() else { return }

        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.defaultsKey) as? Date
        guard last != resetsAt else { return }
        defaults.set(resetsAt, forKey: Self.defaultsKey)

        schedule(at: resetsAt,
                 title: "Claude session refreshed",
                 body: "Your 5-hour usage window has reset — full capacity again.")
    }

    /// Debug hook: `-debugNotifyIn <seconds>` fires a test notification.
    func scheduleDebugIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-debugNotifyIn"), i + 1 < args.count,
              let seconds = TimeInterval(args[i + 1]) else { return }
        schedule(at: Date().addingTimeInterval(seconds),
                 title: "Claude session refreshed",
                 body: "(test) Your 5-hour usage window has reset.")
        NSLog("Notifier: debug notification scheduled in \(seconds)s")
    }

    private func schedule(at date: Date, title: String, body: String) {
        if useUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger)) { error in
                if let error {
                    NSLog("Notifier: UN scheduling failed (\(error)), falling back")
                    Task { @MainActor in self.scheduleFallback(at: date, title: title, body: body) }
                }
            }
        } else {
            scheduleFallback(at: date, title: title, body: body)
        }
    }

    private func scheduleFallback(at date: Date, title: String, body: String) {
        fallbackTask?.cancel()
        fallbackTask = Task {
            let interval = date.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            Self.postViaOsascript(title: title, body: body)
        }
    }

    private static func postViaOsascript(title: String, body: String) {
        func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escaped(body))\" with title \"\(escaped(title))\" sound name \"Glass\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
