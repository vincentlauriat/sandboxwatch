import Foundation

/// What can be done to a web app. Nothing else, ever.
public enum AzAction: String, Codable, Equatable, CaseIterable {
    case start, stop, restart
}

/// One attempt, performed or refused.
public struct ActionRecord: Codable, Equatable {
    public enum Outcome: Equatable {
        case performed(exitCode: Int32)
        case refused(String)
    }

    public let at: Date
    public let sandbox: String
    public let app: String
    public let action: AzAction
    public let outcome: Outcome

    public init(at: Date, sandbox: String, app: String, action: AzAction, outcome: Outcome) {
        self.at = at
        self.sandbox = sandbox
        self.app = app
        self.action = action
        self.outcome = outcome
    }

    // Flattened on the wire, so a line stays readable with `tail -f` and greppable by hand — the
    // journal is read when something has already gone wrong.
    private enum CodingKeys: String, CodingKey {
        case at, sandbox, app, action, outcome, exitCode, reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        sandbox = try c.decode(String.self, forKey: .sandbox)
        app = try c.decode(String.self, forKey: .app)
        action = try c.decode(AzAction.self, forKey: .action)
        switch try c.decode(String.self, forKey: .outcome) {
        case "performed": outcome = .performed(exitCode: try c.decode(Int32.self, forKey: .exitCode))
        case "refused":   outcome = .refused(try c.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome, in: c, debugDescription: "unknown outcome")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at, forKey: .at)
        try c.encode(sandbox, forKey: .sandbox)
        try c.encode(app, forKey: .app)
        try c.encode(action, forKey: .action)
        switch outcome {
        case .performed(let code):
            try c.encode("performed", forKey: .outcome)
            try c.encode(code, forKey: .exitCode)
        case .refused(let reason):
            try c.encode("refused", forKey: .outcome)
            try c.encode(reason, forKey: .reason)
        }
    }
}

/// An append-only record of every action attempted, refused ones included.
///
/// The local equivalent of `hpm`'s task journal. A journal that recorded only what happened would
/// be silent about the afternoon spent wondering why nothing did.
public final class ActionJournal {
    public static let defaultPath = "~/.config/sbw/actions.jsonl"
    private let path: String

    public init(path: String = ActionJournal.defaultPath) {
        self.path = expandPath(path)
    }

    /// One JSON object per line, appended with a file handle and never rewritten. A journal you
    /// can lose by crashing mid-write is worse than no journal.
    public func append(_ record: ActionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        var line = try encoder.encode(record)
        line.append(contentsOf: [0x0A])

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    /// A missing or unreadable journal is an empty one, and one malformed line does not hide the
    /// others — this is read when something has already gone wrong.
    public func records() -> [ActionRecord] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? SandboxJSON.decoder.decode(ActionRecord.self, from: Data($0.utf8)) }
    }
}
