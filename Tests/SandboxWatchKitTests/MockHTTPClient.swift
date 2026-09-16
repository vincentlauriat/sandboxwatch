import Foundation
@testable import SandboxWatchKit

/// Test double: records every request and answers stubs matched on the URL's path.
final class MockHTTPClient: HTTPClient {
    struct Request {
        let method: String
        let url: URL
        let headers: [String: String]
    }

    private(set) var requests: [Request] = []
    private var stubs: [(path: String, response: HTTPResponse)] = []
    private var failures: [(path: String, message: String)] = []

    func stub(path: String, status: Int, json: String, headers: [String: String] = [:]) {
        stub(path: path, status: status, body: Data(json.utf8), headers: headers)
    }

    func stub(path: String, status: Int, body: Data, headers: [String: String] = [:]) {
        stubs.append((path, HTTPResponse(statusCode: status, headers: headers, body: body)))
    }

    func fail(path: String, message: String) {
        failures.append((path, message))
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try answer("GET", url, headers)
    }

    func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try answer("POST", url, headers)
    }

    private func answer(_ method: String, _ url: URL, _ headers: [String: String]) throws -> HTTPResponse {
        requests.append(Request(method: method, url: url, headers: headers))
        if let failure = failures.last(where: { url.path.contains($0.path) }) {
            throw SandboxWatchError(failure.message)
        }
        guard let stub = stubs.last(where: { url.path.contains($0.path) }) else {
            throw SandboxWatchError("MockHTTPClient: no stub for \(url.path)")
        }
        return stub.response
    }
}
