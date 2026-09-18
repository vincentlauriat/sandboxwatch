import Foundation

/// What one poll of one sandbox found.
///
/// A value, not a rendered line: the CLI prints it, and the menu bar app turns it into an icon
/// and a notification. Every new event is carried, including the quiet ones — filtering is the
/// caller's policy, and a Kit that pre-filtered would impose one policy on both surfaces.
public struct SandboxWatchReport {
    public let findings: [Doctor.Finding]
    public let transition: LiaisonTransition?
    public let newEvents: [ChangeEvent]
    /// The change log moved by more than one page: some events are missing from `newEvents`.
    public let overflowed: Bool

    /// Nothing to announce. A steady state with no new events.
    public var isSilent: Bool { transition == nil && newEvents.isEmpty && !overflowed }
}

/// One poll of one sandbox.
///
/// This lives in the Kit rather than beside the command because an Xcode app target can link the
/// `SandboxWatchKit` library product but cannot import the `sbw` executable target. Batch A1 put
/// it in the executable and described it as the call the menu bar needs; the shape was right and
/// the address was not.
public enum SandboxWatcher {
    public static func poll(
        sandbox: String,
        client: SandboxAPIClient,
        liaison: LiaisonStore,
        cursors: CursorStore,
        at now: Date = Date(),
        limit: Int = SandboxAPI.defaultChangeLimit
    ) async throws -> SandboxWatchReport {
        let findings = await Doctor(client: client).diagnose()

        let decision = LiaisonMonitor.decide(
            observed: Set(findings.map(\.kind)),
            previous: try liaison.state(for: sandbox), at: now)
        try liaison.setState(decision.state, for: sandbox)

        // A sandbox that cannot be reached cannot serve its change log either. That must not
        // swallow the transition, which is the reason for polling in the first place.
        var newEvents: [ChangeEvent] = []
        var overflowed = false
        if let page = try? await client.changes(limit: limit) {
            let scan = ChangeCursor.scan(page: page, since: try cursors.mark(for: sandbox))
            newEvents = scan.newEvents
            overflowed = scan.overflowed
            if let newest = scan.newest { try cursors.setMark(newest, for: sandbox) }
        }

        return SandboxWatchReport(
            findings: findings, transition: decision.transition,
            newEvents: newEvents, overflowed: overflowed)
    }

    /// The CLI line, or `nil` when there is nothing to say. Markers match `sbw changes`, so both
    /// commands teach one vocabulary.
    public static func render(_ report: SandboxWatchReport, sandbox: String, at now: Date) -> String? {
        guard !report.isSilent else { return nil }
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []

        if report.overflowed {
            lines.append("!  \(sandbox)  older events were not returned — some are missing here")
        }
        if report.transition != nil {
            let headlines = report.findings.map(\.headline).joined(separator: "; ")
            lines.append("!! \(formatter.string(from: now))  \(sandbox)  \(headlines)")
        }
        for event in report.newEvents {
            let marker: String
            switch event.severity {
            case .critical: marker = "!!"
            case .notable: marker = "! "
            case .informational: marker = "  "
            }
            let detail = (event.detail?["message"]?.text).map { " (\($0))" } ?? ""
            lines.append("\(marker) \(formatter.string(from: event.at))  \(sandbox)  \(event.type)  \(event.subject)\(detail)")
        }
        return lines.joined(separator: "\n")
    }
}
