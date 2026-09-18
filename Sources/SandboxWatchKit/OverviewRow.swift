import Foundation

/// One line per sandbox, for the top of the control center.
///
/// Every count here is optional on purpose. The project exists because a revoked Reader role once
/// read as "everything is fine"; a row that turned a `denied` section into `0/0 up` or `0%` would
/// reintroduce that false alarm from the window. An absent count and a collected zero are
/// different facts, and this type keeps them apart.
public struct OverviewRow: Equatable {
    public let sandbox: String
    public let icon: WatchPresentation.StatusIcon
    public let headline: String

    /// `nil` when the apps section did not collect — never `(up: 0, of: 0)`.
    public let apps: (up: Int, of: Int)?
    public let appsUnavailableReason: String?

    /// `nil` when the budget did not collect, and also when it collected nothing. The two are told
    /// apart by `budgetUnavailableReason`.
    public let budgetPercent: Double?
    public let budgetUnavailableReason: String?

    /// `nil` when there is no snapshot to be old.
    public let ageSeconds: Double?
    public let unreadChanges: Int

    public static func == (a: OverviewRow, b: OverviewRow) -> Bool {
        a.sandbox == b.sandbox && a.icon == b.icon && a.headline == b.headline
            && a.apps?.up == b.apps?.up && a.apps?.of == b.apps?.of
            && a.appsUnavailableReason == b.appsUnavailableReason
            && a.budgetPercent == b.budgetPercent
            && a.budgetUnavailableReason == b.budgetUnavailableReason
            && a.ageSeconds == b.ageSeconds && a.unreadChanges == b.unreadChanges
    }

    public static func make(
        sandbox: String, snapshot: Snapshot, ageSeconds: Double, report: SandboxWatchReport
    ) -> OverviewRow {
        let apps: (up: Int, of: Int)? = snapshot.apps.fold(
            ok: { list in (up: list.filter(\.isRunning).count, of: list.count) },
            unavailable: { _ in nil })

        // `first` rather than a sum: the server publishes one entry per budget, and adding
        // percentages of different amounts would produce a number that means nothing.
        let budget: Double? = snapshot.budget.fold(
            ok: { $0.first?.percent }, unavailable: { _ in nil })

        return OverviewRow(
            sandbox: sandbox,
            // The same function the menu bar icon comes from. Two thresholds for one sandbox is
            // how a tool ends up with two vocabularies.
            icon: WatchPresentation.icon(for: report),
            headline: report.findings.map(\.headline).joined(separator: "; "),
            apps: apps,
            appsUnavailableReason: snapshot.apps.unavailableReason,
            budgetPercent: budget,
            budgetUnavailableReason: snapshot.budget.unavailableReason,
            ageSeconds: ageSeconds,
            unreadChanges: report.newEvents.count)
    }

    /// A sandbox with no snapshot at all still gets a row. The one you are looking for must not be
    /// the one that disappears from the list.
    public static func unreachable(sandbox: String, report: SandboxWatchReport) -> OverviewRow {
        OverviewRow(
            sandbox: sandbox,
            icon: WatchPresentation.icon(for: report),
            headline: report.findings.map(\.headline).joined(separator: "; "),
            apps: nil, appsUnavailableReason: nil,
            budgetPercent: nil, budgetUnavailableReason: nil,
            ageSeconds: nil,
            unreadChanges: report.newEvents.count)
    }
}
