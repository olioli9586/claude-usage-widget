import Foundation

@main
enum Main {
    static func main() async {
        if CommandLine.arguments.contains("--once") {
            await runOnce()
        } else {
            ClaudeUsageApp.main()
        }
    }

    /// Headless smoke test: fetch once, print the result, write the snapshot.
    static func runOnce() async {
        do {
            let token = try KeychainToken.accessToken()
            print("token: ...\(token.suffix(8))")
            let client = UsageAPIClient()
            let raw = try await client.fetchRaw(token: token)
            if let pretty = try? JSONSerialization.jsonObject(with: raw),
               let data = try? JSONSerialization.data(withJSONObject: pretty, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            let (five, seven) = try client.parse(raw)
            func describe(_ name: String, _ w: UsageWindow?) {
                guard let w else { return print("\(name): none") }
                let reset = w.resetsAt.map { ISO8601.formatter.string(from: $0) } ?? "n/a"
                print("\(name): \(w.utilization)% — resets \(reset)")
            }
            describe("five_hour", five)
            describe("seven_day", seven)
            let snapshot = UsageSnapshot(fetchedAt: Date(), status: .ok, fiveHour: five, sevenDay: seven)
            SnapshotStore.write(snapshot)
            print("snapshot written to \(SnapshotStore.fileURL.path)")
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
