import Foundation

/// How serious a change is. The server judges this — it knows what a change *is* — and the
/// client reads its verdict rather than re-deriving one.
public enum ChangeSeverity: String, Comparable, Codable, CaseIterable {
    case informational
    case notable
    case critical

    private var rank: Int {
        switch self {
        case .informational: return 0
        case .notable:       return 1
        case .critical:      return 2
        }
    }

    public static func < (lhs: ChangeSeverity, rhs: ChangeSeverity) -> Bool {
        lhs.rank < rhs.rank
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

extension ChangeSeverity {
    /// The marker every surface prints, of one fixed width so columns line up.
    ///
    /// It lives here because it was written twice — in `sbw changes` and in `sbw watch` — and the
    /// two had already drifted: `"!"` against `"! "`, which shifted every critical line of
    /// `sbw changes` one character to the right. One vocabulary means one definition.
    public var marker: String {
        switch self {
        case .critical:      return "!!"
        case .notable:       return "! "
        case .informational: return "  "
        }
    }
}

public struct ChangeEvent: Decodable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String
    public let collector: String?
    public let detail: [String: JSONValue]?

    /// What the server said, when it says it. A raw string rather than `ChangeSeverity` so a
    /// value this client does not know cannot fail the whole decode.
    private let publishedSeverity: String?

    private enum CodingKeys: String, CodingKey {
        case at, type, subject, collector, detail
        case publishedSeverity = "severity"
    }

    public var mark: ChangeMark { ChangeMark(at: at, type: type, subject: subject) }

    /// The server's verdict, or — against a server older than 2026-09-17 — the dated table in
    /// `SandboxAPI`.
    ///
    /// A published value this client does not understand becomes `notable`: visible, never loud
    /// enough to raise an alarm by itself, and never quiet enough to disappear. An *absent*
    /// field is a different thing entirely and must not be treated the same way, or a
    /// `collector_access_lost` from an older server would be demoted in the one case that
    /// matters.
    /// The server's message in parentheses, or nothing. Written the same way by every surface:
    /// an event naming only an identifier sends the reader back to the terminal.
    public var detailSuffix: String {
        (detail?["message"]?.text).map { " (\($0))" } ?? ""
    }

    public var severity: ChangeSeverity {
        guard let publishedSeverity else { return SandboxAPI.fallbackSeverity(forType: type) }
        return ChangeSeverity(rawValue: publishedSeverity) ?? .notable
    }
}
