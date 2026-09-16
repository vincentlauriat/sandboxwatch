import Foundation

/// The executable half of `AzureSandboxManager/docs/api.md`. Routes, header names, limits and
/// status codes live here so a server change breaks a test rather than a screen.
public enum SandboxAPI {
    public static let tokenHeader = "X-Sandbox-Token"
    public static let refreshSkippedHeader = "X-Refresh-Skipped"
    public static let changeLimits: ClosedRange<Int> = 1...500
    public static let defaultChangeLimit = 50

    public enum Route: Equatable {
        case snapshot
        case apps
        case changes(limit: Int)
        case refresh
        case healthz
    }

    public static func requiresToken(_ route: Route) -> Bool {
        if case .healthz = route { return false }
        return true
    }

    public static func url(_ route: Route, base: URL) -> URL {
        // A pasted base URL often ends in "/", which would produce "//api/v1/..." and 404.
        let root = URL(string: base.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))) ?? base

        switch route {
        case .snapshot: return root.appendingPathComponent("api/v1/snapshot")
        case .apps:     return root.appendingPathComponent("api/v1/apps")
        case .refresh:  return root.appendingPathComponent("api/v1/refresh")
        case .healthz:  return root.appendingPathComponent("healthz")
        case .changes(let limit):
            let clamped = min(max(limit, changeLimits.lowerBound), changeLimits.upperBound)
            var components = URLComponents(
                url: root.appendingPathComponent("api/v1/changes"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: String(clamped))]
            return components.url!
        }
    }

    /// Returns `nil` for a success, or the modelled failure for a documented status code.
    public static func failure(forStatus status: Int, body: Data) -> APIFailure? {
        switch status {
        case 200..<300: return nil
        case 401:       return .unauthorised
        case 404:       return .notFound
        case 503:       return .noSnapshot
        case 500:       return .serverError(errorMessage(in: body))
        default:        return .unexpected(status: status)
        }
    }

    private static func errorMessage(in body: Data) -> String? {
        struct Envelope: Decodable { let error: String?; let message: String? }
        return (try? SandboxJSON.decoder.decode(Envelope.self, from: body))?.message
    }
}

/// Every way a call can fail to produce data. These are values, not thrown programmer errors:
/// each one is a state the CLI and the app must display and explain.
public enum APIFailure: Error, Equatable {
    case unauthorised
    case noSnapshot
    case notFound
    case serverError(String?)
    case unexpected(status: Int)
    case transport(String)
    case malformed(String)

    public var explanation: String {
        switch self {
        case .unauthorised:
            return "the token was refused — check the one stored for this sandbox"
        case .noSnapshot:
            return "the app is up but has not collected yet — wait for the next collection"
        case .notFound:
            return "no such route — the server may be older than this client"
        case .serverError(let message):
            return "the server failed: \(message ?? "no detail given")"
        case .unexpected(let status):
            return "unexpected HTTP status \(status)"
        case .transport(let message):
            return "could not reach the app: \(message)"
        case .malformed(let message):
            return "the response did not match the API contract: \(message)"
        }
    }
}
