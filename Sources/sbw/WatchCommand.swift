import ArgumentParser
import Foundation
import SandboxWatchKit

enum WatchCommands {
    /// One poll. Returns the line to show, or `nil` when nothing changed.
    ///
    /// The loop lives in the command; this is the whole decision, so it is testable with no
    /// timing — and it is exactly the call the menu bar app needs.
    static func pollOnce(
        sandbox: String,
        client: SandboxAPIClient,
        liaison: LiaisonStore,
        at now: Date = Date()
    ) async throws -> String? {
        let findings = await Doctor(client: client).diagnose()
        let observed = Set(findings.map(\.kind))

        let decision = LiaisonMonitor.decide(
            observed: observed, previous: try liaison.state(for: sandbox), at: now)
        try liaison.setState(decision.state, for: sandbox)

        guard decision.transition != nil else { return nil }

        let formatter = ISO8601DateFormatter()
        let headlines = findings.map(\.headline).joined(separator: "; ")
        return "!! \(formatter.string(from: now))  \(sandbox)  \(headlines)"
    }
}

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Poll a sandbox and report only when its state changes.")

    @Argument var name: String
    @Option(help: "Seconds between polls.") var interval: Int = 300
    @Flag(name: .long, help: "Poll once and exit.") var once = false

    func run() async throws {
        let client = try liveClient(for: name)
        let liaison = LiaisonStore()

        repeat {
            if let line = try await WatchCommands.pollOnce(
                sandbox: name, client: client, liaison: liaison) {
                print(line)
            }
            if once { return }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } while true
    }
}
