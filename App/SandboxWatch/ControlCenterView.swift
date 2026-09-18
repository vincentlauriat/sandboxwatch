import SwiftUI
import SandboxWatchKit

/// Everything one poll learned about one sandbox, kept so the tabs can be opened without asking
/// the sandbox again.
struct SandboxDetailData {
    let snapshot: Snapshot
    let ageSeconds: Double
    let findings: [Doctor.Finding]
    /// What this poll reported as new. The Changes tab is "since the last check", the same
    /// question `sbw changes` answers, from the app's own cursor.
    let changes: [ChangeEvent]
    let apps: [String]
}

/// The window's root: the overview, and the tabs for whichever sandbox is selected.
struct ControlCenterView: View {
    let rows: [OverviewRow]
    let details: [String: SandboxDetailData]
    let actions: (String, [String]) -> ActionsTabView.Model
    let refresh: () -> Void

    @State private var selected: String?

    var body: some View {
        NavigationSplitView {
            List(rows, id: \.sandbox, selection: $selected) { row in
                SandboxRowView(row: row).tag(row.sandbox)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .toolbar {
                Button(String(localized: "Refresh now"), action: refresh)
            }
        } detail: {
            if let selected, let data = details[selected] {
                SandboxTabsView(
                    sandbox: selected, snapshot: data.snapshot, ageSeconds: data.ageSeconds,
                    findings: data.findings, changes: data.changes,
                    actions: actions(selected, data.apps))
            } else if rows.isEmpty {
                Text(String(localized: "No sandbox declared — run sbw sandbox add"))
                    .foregroundStyle(.secondary)
            } else if let selected {
                // Selected, but this poll brought back no snapshot: unreachable, or the token was
                // refused. The row on the left already says which; saying nothing here would read
                // as "still loading".
                VStack(spacing: 6) {
                    Label(String(localized: "No snapshot for this sandbox"), systemImage: "eye.slash")
                    Text(rows.first { $0.sandbox == selected }?.headline ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "Select a sandbox")).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct SandboxRowView: View {
    let row: OverviewRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(row.icon.rawValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.sandbox).font(.body.weight(.medium))
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if row.unreadChanges > 0 {
                Text("\(row.unreadChanges)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch row.icon {
        case .healthy:     return "checkmark.circle"
        case .degraded:    return "exclamationmark.triangle"
        case .unreachable: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch row.icon {
        case .healthy:     return .green
        case .degraded:    return .orange
        case .unreachable: return .red
        }
    }

    // An em dash wherever a section did not collect. Never a zero: `denied` is what a revoked
    // Reader role looks like, and "0/0 up" would read as "everything is fine".
    private var summary: String {
        let apps = row.apps.map { "\($0.up)/\($0.of) up" } ?? "—"
        let budget = row.budgetPercent.map { "\(Int($0))%" } ?? "—"
        let age = row.ageSeconds.map { "\(Int($0))s" } ?? "—"
        return "\(apps) · \(budget) · \(age)"
    }
}
