import Foundation

public enum SandboxJSON {
    /// `JSONDecoder.DateDecodingStrategy.iso8601` rejects fractional seconds, and the server
    /// documents `"2026-09-16T08:00:00.000Z"`. Using the built-in strategy would fail on every
    /// snapshot. Both spellings are accepted here, and nothing else is.
    public static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) { return date }
            if let date = withoutFraction.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "expected an ISO 8601 instant, got '\(raw)'"))
        }
        return decoder
    }()
}
