import ArgumentParser
import Foundation
import SandboxWatchKit

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
            if let line = try await SandboxWatcher.pollOnce(
                sandbox: name, client: client, liaison: liaison) {
                print(line)
            }
            if once { return }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } while true
    }
}
