import SwiftUI

struct MenuView: View {
    let poller: Poller
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            UsageBar(title: "5h session", window: poller.snapshot.fiveHour)
            UsageBar(title: "Weekly", window: poller.snapshot.sevenDay)

            countdown

            statusLine

            Divider()

            HStack {
                Button("Refresh Now") { poller.refreshNow() }
                Spacer()
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .disabled(!LoginItem.isSupported)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do { try LoginItem.setEnabled(newValue) } catch {
                            NSLog("LoginItem toggle failed: \(error)")
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            }
            .controlSize(.small)

            Button("Quit ClaudeUsage") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
        .padding(14)
        .frame(width: 260)
    }

    @ViewBuilder
    private var countdown: some View {
        if let resetsAt = poller.snapshot.fiveHour?.resetsAt, resetsAt > Date() {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(
                    "Session resets in \(remaining(until: resetsAt, now: context.date))",
                    systemImage: "arrow.clockwise"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } else {
            Label("No active session window", systemImage: "moon.zzz")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch poller.snapshot.status {
        case .ok:
            Text("Updated \(poller.snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))\(poller.snapshot.isStale ? " — stale" : "")")
                .font(.caption)
                .foregroundStyle(poller.snapshot.isStale ? .orange : .secondary)
        case .rateLimited:
            Text("Rate limited — retrying with backoff")
                .font(.caption)
                .foregroundStyle(.orange)
        case .authNeeded:
            Text("Login expired — open Claude Code once to log in again")
                .font(.caption)
                .foregroundStyle(.red)
        case .error:
            Text(poller.lastError ?? "Couldn't reach the usage API")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }
}

struct UsageBar: View {
    let title: String
    let window: UsageWindow?

    private var fraction: Double { min(max((window?.utilization ?? 0) / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(color)
        }
    }

    private var color: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }
}
