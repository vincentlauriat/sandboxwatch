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

/// A value inside an event's `detail`. The server puts whatever describes the change there —
/// `{"from": 200, "to": null}` for a probe, `{"role": "b24988ac"}` for an assignment — so the
/// model has to accept a string, a number, a boolean or null. Declaring it `[String: String]`
/// made every `sbw changes` call fail against a real log.
public enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        self = .string(try container.decode(String.self))
    }

    /// How an operator should see it. `nil` for null, so a caller can skip it rather than
    /// print the word "null".
    public var text: String? {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .null: return nil
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value))
                : String(value)
        }
    }
}

public struct ChangeEvent: Decodable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String
    public let collector: String?
    public let detail: [String: JSONValue]?

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
