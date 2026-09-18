import Foundation

/// One poll of one sandbox.
///
/// This lives in the Kit rather than beside the command because an Xcode app target can link the
/// `SandboxWatchKit` library product but cannot import the `sbw` executable target. Batch A1 put
/// it in the executable and described it as the call the menu bar needs; the shape was right and
/// the address was not.
public enum SandboxWatcher {
    /// Returns the line to show, or `nil` when nothing changed.
    public static func pollOnce(
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
