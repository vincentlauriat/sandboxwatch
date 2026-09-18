import SwiftUI
import SandboxWatchKit

/// One row per sandbox. Layout only: every value shown here was decided in `OverviewRow`.
struct OverviewView: View {
    let rows: [OverviewRow]
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sandboxes").font(.headline)
                Spacer()
                Button(String(localized: "Refresh now"), action: refresh)
            }
            .padding()

            Divider()

            if rows.isEmpty {
                Text(String(localized: "No sandbox declared — run sbw sandbox add"))
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(rows, id: \.sandbox) { row in
                    SandboxRowView(row: row)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 620, minHeight: 360)
    }
}

private struct SandboxRowView: View {
    let row: OverviewRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(row.icon.rawValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.sandbox).font(.body.weight(.medium))
                Text(row.headline).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(apps).monospacedDigit().foregroundStyle(.secondary)
            Text(budget).monospacedDigit().foregroundStyle(.secondary)
            Text(age).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

    // An em dash, never a zero. A section that did not collect has no number, and inventing one
    // here would be the false alarm this project exists to remove.
    private var apps: String {
        guard let apps = row.apps else { return "—" }
        return "\(apps.up)/\(apps.of) up"
    }

    private var budget: String {
        guard let percent = row.budgetPercent else { return "—" }
        return "\(Int(percent))%"
    }

    private var age: String {
        guard let seconds = row.ageSeconds else { return "—" }
        return "\(Int(seconds))s"
    }
}
