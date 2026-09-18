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

    /// Forces a collection, then returns the resulting snapshot and whether the server skipped
    /// the refresh. Rate-limited to once per 30 s: beyond that the server returns the current
    /// snapshot with `X-Refresh-Skipped: true` rather than an error, and that flag has to reach
    /// the caller — a confirmation prompt that hid it would claim freshness it does not have.
    public func refresh() async throws -> (response: SnapshotResponse, skipped: Bool) {
        let url = SandboxAPI.url(.refresh, base: baseURL)
        let http: HTTPResponse
        do {
            http = try await self.http.post(url, headers: [SandboxAPI.tokenHeader: token])
        } catch let failure as APIFailure {
            throw failure
        } catch {
            throw APIFailure.transport(error.localizedDescription)
        }

        if let failure = SandboxAPI.failure(forStatus: http.statusCode, body: http.body) {
            throw failure
        }
        do {
            let decoded = try SandboxJSON.decoder.decode(SnapshotResponse.self, from: http.body)
            return (decoded, http.header(SandboxAPI.refreshSkippedHeader) == "true")
        } catch {
            throw APIFailure.malformed("\(error)")
        }
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
            // `localizedDescription`, never `\(error)`: URLSession throws an NSError whose
            // interpolation dumps 400 characters of userInfo, and this string ends up on a
            // `sbw watch` line and in a notification body.
            throw APIFailure.transport(error.localizedDescription)
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
