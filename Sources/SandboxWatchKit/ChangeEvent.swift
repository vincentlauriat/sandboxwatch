import Foundation

public enum ChangeSeverity: Int, Comparable, Codable {
    case informational
    case notable
    case critical

    public static func < (lhs: ChangeSeverity, rhs: ChangeSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A cursor's identity. Not `at` alone: timestamps are not guaranteed unique — several events
/// share one collection instant — and a time-only cursor either replays a tie or drops it.
public struct ChangeMark: Codable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String

    public init(at: Date, type: String, subject: String) {
        self.at = at
        self.type = type
        self.subject = subject
    }
}

public struct ChangeEvent: Decodable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String
    public let collector: String?
    public let detail: [String: String]?

    public var mark: ChangeMark { ChangeMark(at: at, type: type, subject: subject) }

    /// Losing or regaining collector access is the incident this project was written after:
    /// a Contributor role moved over a weekend with no notification. It gets its own level, so
    /// it is never queued behind a probe that flapped.
    public var severity: ChangeSeverity {
        switch type {
        case "collector_access_lost", "collector_access_restored":
            return .critical
        case "role_added", "role_removed", "lock_added", "lock_removed",
             "deny_assignment_added", "deny_assignment_removed", "budget_threshold_crossed":
            return .notable
        default:
            return .informational
        }
    }
}
