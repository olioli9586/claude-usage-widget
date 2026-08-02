import AppKit
import Observation

@MainActor
@Observable
final class Poller {
    private(set) var snapshot: UsageSnapshot
    private(set) var lastError: String?

    private let client = UsageAPIClient()
    private let tokens = TokenManager()
    let notifier = Notifier()
    private var loopTask: Task<Void, Never>?
    private var isFetching = false
    private var consecutiveRateLimits = 0
    private var retryAfterHint: TimeInterval?

    static let baseInterval: TimeInterval = 180

    init() {
        snapshot = SnapshotStore.read() ?? .placeholder
    }

    func start() {
        guard loopTask == nil else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                let delay = self?.nextDelay() ?? Self.baseInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refreshNow() {
        Task { await pollOnce() }
    }

    private func nextDelay() -> TimeInterval {
        if consecutiveRateLimits > 0 {
            let backoff = min(60 * pow(2, Double(consecutiveRateLimits - 1)), 1800)
            return max(backoff, retryAfterHint ?? 0)
        }
        return Self.baseInterval + Double.random(in: -15...15)
    }

    private func pollOnce() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let (five, seven) = try await fetchWindows()
            snapshot = UsageSnapshot(fetchedAt: Date(), status: .ok, fiveHour: five, sevenDay: seven)
            lastError = nil
            consecutiveRateLimits = 0
            retryAfterHint = nil
            SnapshotStore.write(snapshot)
            notifier.scheduleSessionReset(at: five?.resetsAt)
        } catch let error as UsageAPIError {
            switch error {
            case .rateLimited(let retryAfter):
                consecutiveRateLimits += 1
                retryAfterHint = retryAfter
                degrade(to: .rateLimited)
            case .unauthorized:
                degrade(to: .authNeeded)
            case .http:
                degrade(to: .error)
            }
            lastError = error.localizedDescription
        } catch let error as TokenError {
            degrade(to: .authNeeded)
            lastError = error.localizedDescription
        } catch {
            degrade(to: .error)
            lastError = error.localizedDescription
        }
    }

    /// Fetch with a valid token; if the API still rejects it (revoked
    /// server-side despite an unexpired expiry), force one refresh and retry.
    private func fetchWindows() async throws -> (fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        let token = try await tokens.validAccessToken()
        do {
            return try await client.fetch(token: token)
        } catch UsageAPIError.unauthorized {
            return try await client.fetch(token: tokens.refreshedToken())
        }
    }

    /// Keep the last-good usage numbers, only downgrade the status.
    private func degrade(to status: UsageSnapshot.Status) {
        snapshot.status = status
        SnapshotStore.write(snapshot)
    }
}
