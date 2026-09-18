import Foundation

/// Why an action was refused.
///
/// A value, not a thrown error: a refusal is a state the CLI prints and the app shows in a sheet,
/// and every one of them is written to the journal exactly as it is displayed.
public enum ActionRefusal: Error, Equatable {
    /// `az` is pointing at a different subscription from the one the sandbox watches.
    case wrongSubscription(expected: String, actual: String)
    /// `az` cannot answer at all.
    case notLoggedIn(String)
    /// The snapshot could not be refreshed, so its state cannot be trusted for a decision.
    case couldNotConfirmFreshness(String)
    /// The collector could not resolve which subscription it watches — there is nothing to compare.
    case identityUnavailable
    /// The sandbox does not know this app: a typo, or the wrong sandbox.
    case unknownApp(String)

    public var headline: String {
        switch self {
        case .wrongSubscription(let expected, let actual):
            return "az is pointing at subscription \(actual), the sandbox watches \(expected)"
        case .notLoggedIn(let detail):
            return "az cannot answer: \(detail)"
        case .couldNotConfirmFreshness(let detail):
            return "the snapshot could not be refreshed: \(detail)"
        case .identityUnavailable:
            return "the sandbox could not say which subscription it watches"
        case .unknownApp(let name):
            return "this sandbox has no app called '\(name)'"
        }
    }

    public var nextStep: String? {
        switch self {
        case .wrongSubscription(let expected, _):
            return "az account set --subscription \(expected)"
        case .notLoggedIn:
            return "az login"
        case .couldNotConfirmFreshness:
            return "check the web app's log stream in Azure, then try again"
        case .identityUnavailable:
            return "check the managed identity's Reader role on the resource group"
        case .unknownApp:
            return "sbw status <sandbox> lists the apps this sandbox knows"
        }
    }
}

/// What the guards established, and what the confirmation prompt must show.
public struct ActionContext: Equatable {
    public let subscriptionId: String
    public let resourceGroup: String
    public let appState: String?
    public let ageSeconds: Double
    /// The refresh was rate-limited and did not run. The snapshot is current-ish, not current,
    /// and the confirmation says so — a prompt that stayed silent would imply freshly verified
    /// state, which is the one thing the freshness guard exists to guarantee.
    public let refreshSkipped: Bool
}

/// Three guards, in a fixed order, all of them before a single `az webapp` process exists.
public enum ActionGuards {
    public static func check(
        sandbox: String,
        app: String,
        client: SandboxAPIClient,
        runner: ProcessRunner
    ) async -> Result<ActionContext, ActionRefusal> {
        // Guard 3 first. It is the cheapest and most certain refusal, and nothing should touch
        // the network until `az` has proved it can answer at all. Measured 2026-09-18: logged
        // out, `az account show` exits 1 with an empty stdout and does not open a device-code
        // flow — so this preflight can never be the thing that hangs.
        let account: ProcessResult
        do {
            account = try await runner.run(
                AzRunner.executable,
                AzRunner.accountShowArguments)
        } catch {
            return .failure(.notLoggedIn(error.localizedDescription))
        }
        guard account.succeeded, !account.trimmedOutput.isEmpty else {
            let detail = account.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.notLoggedIn(detail.isEmpty ? "az account show exited \(account.exitCode)" : detail))
        }

        // Guard 2. Refresh, then read what the refresh produced — not the snapshot from before it.
        let response: SnapshotResponse
        let skipped: Bool
        do {
            (response, skipped) = try await client.refresh()
        } catch let failure as APIFailure {
            return .failure(.couldNotConfirmFreshness(failure.explanation))
        } catch {
            return .failure(.couldNotConfirmFreshness(error.localizedDescription))
        }

        let identity = response.snapshot.identity
        guard identity.available else { return .failure(.identityUnavailable) }

        // Guard 1. `az` points wherever `az account set` last left it, which has nothing to do
        // with the sandbox on screen.
        guard identity.subscriptionId == account.trimmedOutput else {
            return .failure(.wrongSubscription(
                expected: identity.subscriptionId, actual: account.trimmedOutput))
        }

        let apps = response.snapshot.apps.fold(ok: { $0 }, unavailable: { _ in [] })
        guard let target = apps.first(where: { $0.name == app }) else {
            return .failure(.unknownApp(app))
        }

        return .success(ActionContext(
            subscriptionId: identity.subscriptionId,
            resourceGroup: identity.resourceGroup,
            appState: target.state,
            ageSeconds: response.ageSeconds,
            refreshSkipped: skipped))
    }

}
