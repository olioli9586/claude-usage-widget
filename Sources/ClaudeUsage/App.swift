import SwiftUI

struct ClaudeUsageApp: App {
    @State private var poller = Poller()

    var body: some Scene {
        MenuBarExtra {
            MenuView(poller: poller)
        } label: {
            MenuBarLabel(snapshot: poller.snapshot)
                .task {
                    poller.notifier.requestAuthorization()
                    poller.notifier.scheduleDebugIfRequested()
                    poller.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
    }

    private var text: String {
        guard snapshot.fetchedAt != .distantPast else { return "…" }
        let pct = Int((snapshot.fiveHour?.utilization ?? 0).rounded())
        return "\(pct)%"
    }

    private var symbol: String {
        switch snapshot.status {
        case .ok: return snapshot.isStale ? "clock.badge.exclamationmark" : "gauge.with.needle"
        case .rateLimited: return "hourglass"
        case .authNeeded: return "person.crop.circle.badge.exclamationmark"
        case .error: return "exclamationmark.triangle"
        }
    }
}
