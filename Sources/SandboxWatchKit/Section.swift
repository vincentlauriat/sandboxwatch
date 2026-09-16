import Foundation

/// One collected section of a snapshot.
///
/// There is deliberately **no** `data` property and **no** `T?` accessor. The payload lives
/// inside `.ok`, so it cannot be read without first establishing that the collection
/// succeeded, and there is no optional to write `?? []` against.
///
/// This is not stylistic. AzureSandboxManager compares two snapshots only when both collected
/// a section successfully, because a naive diff would announce that every role assignment
/// disappeared at the very moment a Reader role is revoked. A client that renders a denied
/// section as "0 role assignments" reintroduces that false alarm from the outside — at the
/// worst possible moment, since `denied` is exactly what a revoked role looks like.
public struct Section<T> {
    public enum Outcome {
        case ok(T)
        case denied(message: String?)
        case error(message: String?)
    }

    public let outcome: Outcome
    /// The documented envelope carries `durationMs` on every status, so the model does too.
    public let durationMs: Int

    public init(outcome: Outcome, durationMs: Int) {
        self.outcome = outcome
        self.durationMs = durationMs
    }

    public var isOK: Bool {
        if case .ok = outcome { return true }
        return false
    }

    /// Why this section has no payload, in words fit to show an operator. `nil` when it does.
    public var unavailableReason: String? {
        switch outcome {
        case .ok: return nil
        case .denied(let message): return message ?? "denied"
        case .error(let message): return message ?? "error"
        }
    }

    /// The only way to reach the payload: the caller must also say what an unavailable
    /// section looks like, so "denied" can never fall through to a default empty rendering.
    public func fold<R>(ok: (T) -> R, unavailable: (String) -> R) -> R {
        switch outcome {
        case .ok(let value): return ok(value)
        case .denied, .error: return unavailable(unavailableReason!)
        }
    }
}

extension Section: Decodable where T: Decodable {
    private enum CodingKeys: String, CodingKey {
        case status, data, message, durationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        let message = try container.decodeIfPresent(String.self, forKey: .message)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0

        switch status {
        case "ok":
            self.outcome = .ok(try container.decode(T.self, forKey: .data))
        case "denied":
            self.outcome = .denied(message: message)
        case "error":
            self.outcome = .error(message: message)
        default:
            // A status this client does not know is not a success. Treating it as `.ok` with
            // no data would let the empty-data bug arrive through a future server version.
            self.outcome = .error(message: "unknown collector status '\(status)'")
        }
    }
}
