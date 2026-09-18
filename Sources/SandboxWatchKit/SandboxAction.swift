import Foundation

/// One write action against one sandbox, from the guards to the journal.
///
/// This lives in the Kit, not beside the command, for the same reason `SandboxWatcher` does: an
/// Xcode app target links the `SandboxWatchKit` library product and cannot import the `sbw`
/// executable target. Batch B put it in the executable, and the control center's Actions tab is
/// required to carry the same three guards as the CLI — including the step a second, hand-written
/// copy would quietly drop, which is journalling the refusal.
public enum SandboxAction {
    /// The guards, run **once**. The context returned is the one the confirmation is shown for and
    /// the one the action then uses — checking twice would mean the operator confirms against one
    /// reading and the action departs against another, which is precisely the promise the
    /// freshness guard exists to make.
    public static func prepare(
        sandbox: String, app: String,
        client: SandboxAPIClient, runner: ProcessRunner
    ) async -> Result<ActionContext, ActionRefusal> {
        await ActionGuards.check(sandbox: sandbox, app: app, client: client, runner: runner)
    }

    /// What the confirmation prompt shows. Never a bare "are you sure": the freshness guard exists
    /// so this line can be trusted.
    public static func describe(_ context: ActionContext, sandbox: String, app: String, action: AzAction) -> String {
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

    public static func render(_ refusal: ActionRefusal) -> String {
        var lines = ["refused — \(refusal.headline)"]
        if let step = refusal.nextStep { lines.append("  try: \(step)") }
        return lines.joined(separator: "\n")
    }

    /// Journals a refusal. A refused action is recorded as faithfully as a performed one: the
    /// record has to account for the afternoon spent wondering why nothing happened.
    public static func journal(
        _ refusal: ActionRefusal, sandbox: String, app: String, action: AzAction,
        journal store: ActionJournal, at now: Date = Date()
    ) {
        try? store.append(ActionRecord(
            at: now, sandbox: sandbox, app: app, action: action,
            outcome: .refused(refusal.headline)))
    }

    /// Runs the action against the context the operator confirmed, and records what happened.
    public static func perform(
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

