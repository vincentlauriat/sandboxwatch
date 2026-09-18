import ArgumentParser
import Foundation
import SandboxWatchKit

/// The write half of the CLI. The decisions live in this namespace so they are testable without
/// spawning a process; the `ParsableCommand` structs below only parse arguments and inject
/// dependencies, exactly as `ReadCommands` does.
enum ActionCommands {
    /// What the confirmation prompt shows before anything can be typed. Never a bare
    /// "are you sure": the freshness guard exists so this line can be trusted.
    static func describe(
        sandbox: String, app: String, action: AzAction,
        client: SandboxAPIClient, runner: ProcessRunner
    ) async -> String {
        switch await ActionGuards.check(sandbox: sandbox, app: app, client: client, runner: runner) {
        case .failure(let refusal):
            return render(refusal)
        case .success(let context):
            var lines = [
                "\(action.rawValue) \(app) in \(sandbox)",
                "  subscription  \(context.subscriptionId)",
                "  group         \(context.resourceGroup)",
                "  current state \(context.appState ?? "unknown")",
                "  snapshot age  \(Int(context.ageSeconds))s",
            ]
            if context.refreshSkipped {
                // Two actions in quick succession: the server rate-limited the refresh. Saying
                // nothing here would imply freshly verified state, which is the single thing this
                // guard exists to guarantee.
                lines.append("  the snapshot was not refreshed — rate-limited, so this age is from the previous collection")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Runs the guards, then the action, then records whichever happened.
    static func perform(
        sandbox: String, app: String, action: AzAction,
        client: SandboxAPIClient, runner: ProcessRunner,
        journal: ActionJournal, confirmed: Bool
    ) async -> String {
        guard confirmed else { return "cancelled — nothing was done" }

        let context: ActionContext
        switch await ActionGuards.check(sandbox: sandbox, app: app, client: client, runner: runner) {
        case .failure(let refusal):
            // A refused action is journalled as faithfully as a performed one: the record has to
            // account for the afternoon spent wondering why nothing happened.
            try? journal.append(ActionRecord(
                at: Date(), sandbox: sandbox, app: app, action: action,
                outcome: .refused(refusal.headline)))
            return render(refusal)
        case .success(let value):
            context = value
        }

        do {
            let result = try await AzRunner.perform(
                action, app: app, resourceGroup: context.resourceGroup,
                subscriptionId: context.subscriptionId, runner: runner)
            try? journal.append(ActionRecord(
                at: Date(), sandbox: sandbox, app: app, action: action,
                outcome: .performed(exitCode: result.exitCode)))

            if result.succeeded {
                return "\(action.rawValue) \(app) in \(sandbox): done"
            }
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(action.rawValue) \(app) in \(sandbox): az exited \(result.exitCode)\n\(detail)"
        } catch {
            try? journal.append(ActionRecord(
                at: Date(), sandbox: sandbox, app: app, action: action,
                outcome: .refused("az could not be run: \(error.localizedDescription)")))
            return "az could not be run: \(error.localizedDescription)"
        }
    }

    private static func render(_ refusal: ActionRefusal) -> String {
        var lines = ["refused — \(refusal.headline)"]
        if let step = refusal.nextStep { lines.append("  try: \(step)") }
        return lines.joined(separator: "\n")
    }
}

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
        let journal = ActionJournal()

        print(await ActionCommands.describe(
            sandbox: sandbox, app: app, action: action, client: client, runner: runner))

        var confirmed = yes
        if !yes {
            print("\nType the app's name to confirm: ", terminator: "")
            confirmed = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == app
        }

        print(await ActionCommands.perform(
            sandbox: sandbox, app: app, action: action, client: client,
            runner: runner, journal: journal, confirmed: confirmed))
    }
}
