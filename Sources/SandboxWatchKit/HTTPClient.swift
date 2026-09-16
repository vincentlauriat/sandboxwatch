import Foundation

public struct HTTPResponse {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// HTTP header names are case-insensitive, and URLSession does not promise a casing.
    /// `X-Refresh-Skipped` is read through here, so an exact-match lookup would be a silent bug.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// The network seam. Mocked in every test; `URLSessionHTTPClient` is the only implementation
/// that opens a socket.
public protocol HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
    func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send("GET", url, headers)
    }

    public func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send("POST", url, headers)
    }

    private func send(_ method: String, _ url: URL, _ headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SandboxWatchError("non-HTTP response from \(url)")
        }
        var received: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { received[key] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: received, body: data)
    }
}
