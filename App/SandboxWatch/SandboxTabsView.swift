import SwiftUI
import SandboxWatchKit

/// The per-sandbox tabs. Layout only — every value comes from `SandboxDetail`.
struct SandboxTabsView: View {
    let sandbox: String
    let snapshot: Snapshot
    let ageSeconds: Double
    let findings: [Doctor.Finding]
    let changes: [ChangeEvent]
    let actions: ActionsTabView.Model

    var body: some View {
        TabView {
            summary.tabItem { Text(String(localized: "Summary")) }

            PanelView(panel: SandboxDetail.apps(from: snapshot),
                      emptyMessage: String(localized: "No app in this resource group")) { row in
                AppRowView(row: row)
            }
            .tabItem { Text(String(localized: "Apps & probes")) }

            changesTab.tabItem { Text(String(localized: "Changes")) }

            PanelView(panel: SandboxDetail.governance(from: snapshot),
                      emptyMessage: String(localized: "No role, lock or deny assignment")) { row in
                HStack {
                    Text(row.kind.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(row.label).textSelection(.enabled)
                    Spacer()
                    if let detail = row.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .tabItem { Text(String(localized: "Governance")) }

            PanelView(panel: SandboxDetail.budget(from: snapshot),
                      emptyMessage: String(localized: "No budget defined")) { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    Text(amount(row)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .tabItem { Text(String(localized: "Budget")) }

            ActionsTabView(model: actions).tabItem { Text(String(localized: "Actions")) }
        }
        .padding()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sandbox).font(.title2)
            Text(String(localized: "Snapshot age: \(Int(ageSeconds))s")).foregroundStyle(.secondary)
            Divider()
            ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.headline)
                    if let step = finding.nextStep {
                        Text(step).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var changesTab: some View {
        let rows = SandboxDetail.changes(changes)
        return Group {
            if rows.isEmpty {
                Text(String(localized: "Nothing changed since the last check"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The same two characters `sbw changes` prints.
                        Text(row.marker).font(.body.monospaced())
                            .foregroundStyle(row.severity == .critical ? Color.red : .secondary)
                        Text(row.at.formatted(date: .abbreviated, time: .standard))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(row.type)
                        Text(row.subject).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // No currency symbol invented: the server says which one, or none is shown.
    private func amount(_ row: SandboxDetail.BudgetRow) -> String {
        guard let spent = row.spent, let amount = row.amount else { return "—" }
        let currency = row.currency.map { " \($0)" } ?? ""
        let percent = row.percent.map { " (\(Int($0))%)" } ?? ""
        return "\(Int(spent)) / \(Int(amount))\(currency)\(percent)"
    }
}

private struct AppRowView: View {
    let row: SandboxDetail.AppRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.name)
            Text(row.state ?? String(localized: "unknown state"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(probe).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    /// Three different facts, kept apart: a probe result, "the probes section was refused so this
    /// app's reachability is unknown", and "this app has no probe configured".
    private var probe: String {
        if let probe = row.probe {
            if let error = probe.error { return error }
            let status = probe.httpStatus.map(String.init) ?? "—"
            let latency = probe.latencyMs.map { " \(Int($0))ms" } ?? ""
            return status + latency
        }
        if row.probesUnavailableReason != nil { return String(localized: "probe unknown") }
        return String(localized: "not probed")
    }
}
