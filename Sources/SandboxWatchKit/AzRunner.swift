import Foundation

/// The exact command lines, in one place.
///
/// They are constants rather than strings built at the call site because this is the only code in
/// the project that can stop a running web app. An argv assertion in a test is the difference
/// between "the action succeeded" and "the right action succeeded".
public enum AzRunner {
    /// `az` is reached through `env` so a Homebrew install and an MSI install both resolve, which
    /// means the argv must name `az` itself.
    public static let executable = "/usr/bin/env"

    /// Guard 3's preflight. Measured 2026-09-18: logged out, this exits 1 with an empty stdout and
    /// does not open a device-code flow.
    public static let accountShowArguments = [
        "az", "account", "show", "--query", "id", "--output", "tsv", "--only-show-errors",
    ]

    public static func arguments(
        for action: AzAction, app: String, resourceGroup: String, subscriptionId: String
    ) -> [String] {
        [
            "az", "webapp", action.rawValue,
            "--name", app,
            "--resource-group", resourceGroup,
            // Explicit, never left to whatever `az account set` last selected. Without this the
            // subscription guard would have checked a value it then failed to use.
            "--subscription", subscriptionId,
            // `--only-show-errors` keeps warnings out of the journal; `--output json` keeps the
            // shape stable. A device-code prompt from a menu bar app with no TTY hangs forever.
            "--only-show-errors",
            "--output", "json",
        ]
    }

    /// A non-zero exit is returned, not thrown: an `az` failure is a state the CLI prints and the
    /// journal records.
    public static func perform(
        _ action: AzAction,
        app: String,
        resourceGroup: String,
        subscriptionId: String,
        runner: ProcessRunner
    ) async throws -> ProcessResult {
        try await runner.run(executable, arguments(
            for: action, app: app, resourceGroup: resourceGroup, subscriptionId: subscriptionId))
    }
}
