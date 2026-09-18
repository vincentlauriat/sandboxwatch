import ArgumentParser
import Foundation
import SandboxWatchKit

// MARK: - ArgumentParser wrappers

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start", abstract: "Start a web app, under your own az login.")
    @OptionGroup var options: ActionOptions
    func run() async throws { try await options.run(.start) }
}

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop", abstract: "Stop a web app, under your own az login.")
    @OptionGroup var options: ActionOptions
    func run() async throws { try await options.run(.stop) }
}

struct RestartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart", abstract: "Restart a web app, under your own az login.")
    @OptionGroup var options: ActionOptions
    func run() async throws { try await options.run(.restart) }
}

struct ActionOptions: ParsableArguments {
    @Argument(help: "The sandbox.") var sandbox: String
    @Argument(help: "The web app.") var app: String
    @Flag(name: .long, help: "Skip the confirmation. For scripts.") var yes = false

    func run(_ action: AzAction) async throws {
        let client = try liveClient(for: sandbox)
        let runner = SystemProcessRunner()
        let store = ActionJournal()

        let context: ActionContext
        switch await SandboxAction.prepare(
            sandbox: sandbox, app: app, client: client, runner: runner) {
        case .failure(let refusal):
            SandboxAction.journal(
                refusal, sandbox: sandbox, app: app, action: action, journal: store)
            print(SandboxAction.render(refusal))
            throw ExitCode.failure
        case .success(let value):
            context = value
        }

        print(SandboxAction.describe(context, sandbox: sandbox, app: app, action: action))

        var confirmed = yes
        if !yes {
            print("\nType the app's name to confirm: ", terminator: "")
            confirmed = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == app
        }

        print(await SandboxAction.perform(
            sandbox: sandbox, app: app, action: action, context: context,
            runner: runner, journal: store, confirmed: confirmed))
    }
}
