import Foundation

/// One line of `sbw status`. A view model, not a formatter: the app reuses it.
public struct StatusRow: Equatable {
    public let sandbox: String
    public let age: String
    public let apps: String
    public let budget: String
    public let sections: String
    public let problem: String?

    public init(sandbox: String, age: String, apps: String, budget: String, sections: String, problem: String?) {
        self.sandbox = sandbox
        self.age = age
        self.apps = apps
        self.budget = budget
        self.sections = sections
        self.problem = problem
    }

    public static func make(sandbox: String, response: SnapshotResponse) -> StatusRow {
        let snapshot = response.snapshot

        // `fold` forces both branches: a denied section prints why, never a zero that reads as
        // a measurement.
        let apps = snapshot.apps.fold(
            ok: { apps in "\(apps.filter(\.isRunning).count)/\(apps.count) up" },
            unavailable: { _ in "denied" })

        // The wire sends a list. Show the budget closest to being blown — a second budget at
        // 10% must never hide a first one at 95%.
        let budget = snapshot.budget.fold(
            ok: { budgets in
                budgets.compactMap(\.percent).max().map { "\(Int($0))%" } ?? "—"
            },
            unavailable: { _ in "denied" })

        let unavailable = snapshot.unavailableSections

        return StatusRow(
            sandbox: sandbox,
            age: humanDuration(response.ageSeconds),
            apps: apps,
            budget: budget,
            sections: unavailable.isEmpty ? "all" : unavailable.joined(separator: ","),
            problem: unavailable.isEmpty ? nil : "\(unavailable.joined(separator: ", ")) did not collect")
    }

    public static func unreachable(sandbox: String, failure: APIFailure) -> StatusRow {
        StatusRow(sandbox: sandbox, age: "—", apps: "—", budget: "—", sections: "—",
                  problem: failure.explanation)
    }
}

/// "45s", "2m", "1h5m". Deliberately short: this sits in a table column.
public func humanDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h\(minutes % 60)m"
}

public func renderTable(_ rows: [StatusRow]) -> String {
    let header = ["SANDBOX", "AGE", "APPS", "BUDGET", "SECTIONS"]
    let body = rows.map { [$0.sandbox, $0.age, $0.apps, $0.budget, $0.sections] }
    let all = [header] + body

    let widths = (0..<header.count).map { column in
        all.map { $0[column].count }.max() ?? 0
    }

    return all.map { line in
        line.enumerated()
            .map { index, cell in
                index == line.count - 1 ? cell : cell.padding(toLength: widths[index] + 2, withPad: " ", startingAt: 0)
            }
            .joined()
    }.joined(separator: "\n")
}
