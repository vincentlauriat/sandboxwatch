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
        // Its own cursor: moving the one `sbw changes` uses would make a manual run show
        // nothing. Spec 6.3, amended 2026-09-18.
        let cursors = CursorStore(directory: "~/.config/sbw/cursors-watch")

        repeat {
            let now = Date()
            let report = try await SandboxWatcher.poll(
                sandbox: name, client: client, liaison: liaison, cursors: cursors, at: now)
            if let line = SandboxWatcher.render(report, sandbox: name, at: now) {
                print(line)
            }
            if once { return }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } while true
    }
}
