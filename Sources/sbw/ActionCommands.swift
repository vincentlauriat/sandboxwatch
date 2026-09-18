import ArgumentParser
import Foundation
import SandboxWatchKit

/// The write half of the CLI. The decisions live in this namespace so they are testable without
/// spawning a process; the `ParsableCommand` structs below only parse arguments and inject
/// dependencies, exactly as `ReadCommands` does.
enum ActionCommands {
    /// The guards, run **once**. The context returned is the one the confirmation is shown for and
    /// the one the action then uses — checking twice would mean the operator confirms against one
    /// reading and the action departs against another, which is precisely the promise the
    /// freshness guard exists to make.
    static func prepare(
        sandbox: String, app: String,
        client: SandboxAPIClient, runner: ProcessRunner
    ) async -> Result<ActionContext, ActionRefusal> {
        await ActionGuards.check(sandbox: sandbox, app: app, client: client, runner: runner)
    }

    /// What the confirmation prompt shows. Never a bare "are you sure": the freshness guard exists
    /// so this line can be trusted.
    static func describe(_ context: ActionContext, sandbox: String, app: String, action: AzAction) -> String {
        var lines = [
            "\(action.rawValue) \(app) in \(sandbox)",
            "  subscription  \(context.subscriptionId)",
            "  group         \(context.resourceGroup)",
            "  current state \(context.appState ?? "unknown")",
            "  snapshot age  \(Int(context.ageSeconds))s",
        ]
        if context.refreshSkipped {
            // Two actions in quick succession: the server rate-limited the refresh. Saying nothing
            // here would imply freshly verified state, the single thing this guard guarantees.
            lines.append("  the snapshot was not refreshed — rate-limited, so this age is from the previous collection")
        }
        return lines.joined(separator: "\n")
    }

    static func render(_ refusal: ActionRefusal) -> String {
        var lines = ["refused — \(refusal.headline)"]
        if let step = refusal.nextStep { lines.append("  try: \(step)") }
        return lines.joined(separator: "\n")
    }

    /// Journals a refusal. A refused action is recorded as faithfully as a performed one: the
    /// record has to account for the afternoon spent wondering why nothing happened.
    static func journal(
        _ refusal: ActionRefusal, sandbox: String, app: String, action: AzAction,
        journal store: ActionJournal, at now: Date = Date()
    ) {
        try? store.append(ActionRecord(
            at: now, sandbox: sandbox, app: app, action: action,
            outcome: .refused(refusal.headline)))
    }

    /// Runs the action against the context the operator confirmed, and records what happened.
    static func perform(
        sandbox: String, app: String, action: AzAction, context: ActionContext,
        runner: ProcessRunner, journal store: ActionJournal, confirmed: Bool,
        at now: Date = Date()
    ) async -> String {
        guard confirmed else { return "cancelled — nothing was done" }

        do {
            let result = try await AzRunner.perform(
                action, app: app, resourceGroup: context.resourceGroup,
                subscriptionId: context.subscriptionId, runner: runner)
            try? store.append(ActionRecord(
                at: now, sandbox: sandbox, app: app, action: action,
                outcome: .performed(exitCode: result.exitCode)))

            if result.succeeded {
                return "\(action.rawValue) \(app) in \(sandbox): done"
            }
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(action.rawValue) \(app) in \(sandbox): az exited \(result.exitCode)\n\(detail)"
        } catch {
            try? store.append(ActionRecord(
                at: now, sandbox: sandbox, app: app, action: action,
                outcome: .refused("az could not be run: \(error.localizedDescription)")))
            return "az could not be run: \(error.localizedDescription)"
        }
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
        let store = ActionJournal()

        let context: ActionContext
        switch await ActionCommands.prepare(
            sandbox: sandbox, app: app, client: client, runner: runner) {
        case .failure(let refusal):
            ActionCommands.journal(
                refusal, sandbox: sandbox, app: app, action: action, journal: store)
            print(ActionCommands.render(refusal))
            throw ExitCode.failure
        case .success(let value):
            context = value
        }

        print(ActionCommands.describe(context, sandbox: sandbox, app: app, action: action))

        var confirmed = yes
        if !yes {
            print("\nType the app's name to confirm: ", terminator: "")
            confirmed = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == app
        }

        print(await ActionCommands.perform(
            sandbox: sandbox, app: app, action: action, context: context,
            runner: runner, journal: store, confirmed: confirmed))
    }
}
