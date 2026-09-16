import Foundation

public struct Health: Decodable, Equatable {
    public let status: String
    public let uptimeSeconds: Double
}

/// Typed calls on `/api/v1`. Every documented status code becomes an `APIFailure`, and a body
/// that does not match the contract becomes `.malformed` rather than a plausible-looking empty
/// result.
public struct SandboxAPIClient {
    private let baseURL: URL
    private let token: String
    private let http: HTTPClient

    public init(baseURL: URL, token: String, http: HTTPClient) {
        self.baseURL = baseURL
        self.token = token
        self.http = http
    }

    public func snapshot() async throws -> SnapshotResponse {
        try await get(.snapshot, as: SnapshotResponse.self)
    }

    public func apps() async throws -> AppsResponse {
        try await get(.apps, as: AppsResponse.self)
    }

    public func changes(limit: Int = SandboxAPI.defaultChangeLimit) async throws -> [ChangeEvent] {
        struct Envelope: Decodable { let limit: Int; let events: [ChangeEvent] }
        return try await get(.changes(limit: limit), as: Envelope.self).events
    }

    public func health() async throws -> Health {
        try await get(.healthz, as: Health.self)
    }

    private func get<T: Decodable>(_ route: SandboxAPI.Route, as type: T.Type) async throws -> T {
        let url = SandboxAPI.url(route, base: baseURL)
        let headers = SandboxAPI.requiresToken(route) ? [SandboxAPI.tokenHeader: token] : [:]

        let response: HTTPResponse
        do {
            response = try await http.get(url, headers: headers)
        } catch let failure as APIFailure {
            throw failure
        } catch {
            // Anything the transport throws is a reachability problem, not a server verdict.
            throw APIFailure.transport("\(error)")
        }

        if let failure = SandboxAPI.failure(forStatus: response.statusCode, body: response.body) {
            throw failure
        }

        do {
            return try SandboxJSON.decoder.decode(type, from: response.body)
        } catch {
            throw APIFailure.malformed("\(error)")
        }
    }
}
