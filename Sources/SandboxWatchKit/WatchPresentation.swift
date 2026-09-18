import Foundation

/// What a `SandboxWatchReport` means to a person looking at a menu bar.
///
/// These are decisions, so they live here and not in the app target. The CLI and the app read one
/// sandbox; letting each pick its own threshold would give it two vocabularies. The app target is
/// left with what cannot be asserted in a test: an `NSStatusItem`, a notification request, a timer.
public enum WatchPresentation {
    /// Three states, because that is how many an icon can carry at a glance.
    public enum StatusIcon: String, Equatable, CaseIterable {
        case healthy, degraded, unreachable
    }

    /// Something worth interrupting for, with the text a notification shows.
    public struct Alert: Equatable {
        public let title: String
        public let body: String
        public let severity: ChangeSeverity

        public init(title: String, body: String, severity: ChangeSeverity) {
            self.title = title
            self.body = body
            self.severity = severity
        }
    }

    /// An unreachable sandbox is not a degraded one: it is the state in which every other reading
    /// is unknown. A refused token belongs in the same class — nothing can be read — and `Doctor`
    /// keeps the two causes apart in its headline.
    public static func icon(for report: SandboxWatchReport) -> StatusIcon {
        let kinds = Set(report.findings.map(\.kind))
        if kinds.contains(.unreachable) || kinds.contains(.unauthorised) || kinds.contains(.notCollectedYet) {
            return .unreachable
        }
        return report.findings.contains(where: \.isProblem) ? .degraded : .healthy
    }

    /// What warrants interrupting. Deliberately narrow: a transition, a critical event, or a page
    /// that did not reach back far enough. A tool that notifies on everything teaches its operator
    /// to dismiss it, and the one notification that mattered goes with the rest.
    public static func alerts(for report: SandboxWatchReport, sandbox: String) -> [Alert] {
        var alerts: [Alert] = []

        if report.overflowed {
            alerts.append(Alert(
                title: sandbox,
                body: "older events were not returned — some changes are missing",
                severity: .critical))
        }

        if report.transition != nil {
            let headlines = report.findings.map(\.headline).joined(separator: "; ")
            alerts.append(Alert(title: sandbox, body: headlines, severity: .critical))
        }

        for event in report.newEvents where event.severity == .critical {
            // The detail is the point. `collector_access_lost governance` sends you back to the
            // terminal; the same line with the Azure message tells you a role assignment moved.
            let detail = (event.detail?["message"]?.text).map { " (\($0))" } ?? ""
            alerts.append(Alert(
                title: sandbox,
                body: "\(event.type) \(event.subject)\(detail)",
                severity: .critical))
        }

        return alerts
    }
}
