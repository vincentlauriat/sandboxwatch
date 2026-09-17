import ArgumentParser
import Foundation
import SandboxWatchKit

/// `AsyncParsableCommand` rather than `ParsableCommand`: every command that reads the API is
/// asynchronous, and only an async root awaits an async subcommand.
@main
struct SBW: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sbw",
        abstract: "Read the state of your Azure sandboxes, and what changed since last time.",
        subcommands: [SandboxCommand.self, StatusCommand.self, DoctorCommand.self,
                      ChangesCommand.self, WatchCommand.self]
    )
}
