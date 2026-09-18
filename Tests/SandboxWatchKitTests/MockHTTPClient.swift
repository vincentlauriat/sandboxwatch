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

    /// What a guard test asks: was the network touched at all before the refusal?
    var requestedPaths: [String] { requests.map(\.url.path) }
    private var stubs: [(path: String, response: HTTPResponse)] = []
    private var failures: [(path: String, error: Error)] = []

    func stub(path: String, status: Int, json: String, headers: [String: String] = [:]) {
        stub(path: path, status: status, body: Data(json.utf8), headers: headers)
    }

    func stub(path: String, status: Int, body: Data, headers: [String: String] = [:]) {
        stubs.append((path, HTTPResponse(statusCode: status, headers: headers, body: body)))
    }

    func fail(path: String, message: String) {
        failures.append((path, SandboxWatchError(message)))
    }

    /// Fails with an arbitrary error, so a test can reproduce what URLSession really throws:
    /// an NSError whose `\(error)` dumps its whole userInfo.
    func fail(path: String, error: Error) {
        failures.append((path, error))
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
            throw failure.error
        }
        guard let stub = stubs.last(where: { url.path.contains($0.path) }) else {
            throw SandboxWatchError("MockHTTPClient: no stub for \(url.path)")
        }
        return stub.response
    }
}
