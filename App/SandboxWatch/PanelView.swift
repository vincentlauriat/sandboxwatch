import SwiftUI
import SandboxWatchKit

/// Renders a `Panel` the only way it may be rendered: rows, or the reason there are none.
///
/// It exists so no tab can quietly show an unavailable section as an empty table. That is the
/// difference between "no role assignments" and "we were refused permission to look", and the
/// second one is a revoked Reader role.
struct PanelView<Row: Equatable, Content: View>: View {
    let panel: Panel<Row>
    let emptyMessage: String
    @ViewBuilder let row: (Row) -> Content

    var body: some View {
        switch panel {
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "This section could not be collected"), systemImage: "eye.slash")
                    .font(.body.weight(.medium))
                Text(reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()

        case .rows(let rows) where rows.isEmpty:
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()

        case .rows(let rows):
            List(Array(rows.enumerated()), id: \.offset) { row($0.element) }
                .listStyle(.inset)
        }
    }
}
