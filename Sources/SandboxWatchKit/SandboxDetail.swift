import Foundation

/// A tab's worth of rows, or the reason there are none.
///
/// The type exists so a view cannot render an unavailable section as an empty table. An empty
/// table and a refused one look identical on screen, and one of them is a revoked Reader role —
/// which is the incident this whole project was built after.
public enum Panel<Row: Equatable>: Equatable {
    case rows([Row])
    case unavailable(String)
}

/// What each per-sandbox tab shows. Shaping only: no formatting decisions, so the SwiftUI views
/// own layout and nothing else, and the CLI could print the same rows tomorrow.
public enum SandboxDetail {
    // MARK: - Apps and probes

    public struct AppRow: Equatable {
        public let name: String
        public let state: String?
        public let url: String?
        public let probe: Probe?
        /// Set when the apps collected but the probes did not: this app's reachability is
        /// *unknown*, which is not the same as "not probed".
        public let probesUnavailableReason: String?
    }

    public static func apps(from snapshot: Snapshot) -> Panel<AppRow> {
        let probesByApp = snapshot.probes.fold(
            ok: { Dictionary($0.map { ($0.app, $0) }, uniquingKeysWith: { first, _ in first }) },
            unavailable: { _ in [:] })
        let probesReason = snapshot.probes.unavailableReason

        return snapshot.apps.fold(
            ok: { apps in
                .rows(apps.map { app in
                    AppRow(name: app.name, state: app.state, url: app.url,
                           probe: probesByApp[app.name],
                           probesUnavailableReason: probesReason)
                })
            },
            unavailable: { .unavailable($0) })
    }

    // MARK: - Governance

    public struct GovernanceRow: Equatable {
        public enum Kind: String, Equatable { case role, lock, denyAssignment }
        public let kind: Kind
        public let label: String
        public let detail: String?
    }

    public static func governance(from snapshot: Snapshot) -> Panel<GovernanceRow> {
        snapshot.governance.fold(
            ok: { governance in
                var rows: [GovernanceRow] = []
                for role in governance.roleAssignments ?? [] {
                    rows.append(GovernanceRow(
                        kind: .role,
                        label: role.principalId ?? role.id ?? "unknown principal",
                        detail: role.roleDefinitionId))
                }
                for lock in governance.locks ?? [] {
                    rows.append(GovernanceRow(
                        kind: .lock, label: lock.name ?? "unnamed lock", detail: lock.level))
                }
                for deny in governance.denyAssignments ?? [] {
                    rows.append(GovernanceRow(kind: .denyAssignment, label: deny, detail: nil))
                }
                return .rows(rows)
            },
            unavailable: { .unavailable($0) })
    }

    // MARK: - Budget

    public struct BudgetRow: Equatable {
        public let name: String
        public let spent: Double?
        public let amount: Double?
        public let currency: String?
        public let percent: Double?
        public let timeGrain: String?
    }

    public static func budget(from snapshot: Snapshot) -> Panel<BudgetRow> {
        snapshot.budget.fold(
            ok: { budgets in
                .rows(budgets.map {
                    BudgetRow(name: $0.name ?? "budget", spent: $0.spent, amount: $0.amount,
                              currency: $0.currency, percent: $0.percent, timeGrain: $0.timeGrain)
                })
            },
            unavailable: { .unavailable($0) })
    }

    // MARK: - Changes

    public struct ChangeRow: Equatable {
        public let at: Date
        public let marker: String
        public let type: String
        public let subject: String
        public let severity: ChangeSeverity
    }

    /// The marker comes from `ChangeSeverity`, the same one `sbw changes` and `sbw watch` print.
    /// Three surfaces, one vocabulary.
    public static func changes(_ events: [ChangeEvent]) -> [ChangeRow] {
        events.map {
            ChangeRow(at: $0.at, marker: $0.severity.marker, type: $0.type,
                      subject: $0.subject + $0.detailSuffix, severity: $0.severity)
        }
    }
}
