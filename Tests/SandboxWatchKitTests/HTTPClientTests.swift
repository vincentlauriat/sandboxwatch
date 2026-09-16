import XCTest
@testable import SandboxWatchKit

final class HTTPClientTests: XCTestCase {
    // The server sends `X-Refresh-Skipped`; HTTP header names are case-insensitive and
    // URLSession may hand them back in any casing. A case-sensitive lookup would silently
    // miss the one header a guard depends on.
    func testHeaderLookupIsCaseInsensitive() {
        let response = HTTPResponse(statusCode: 200, headers: ["x-refresh-skipped": "true"], body: Data())
        XCTAssertEqual(response.header("X-Refresh-Skipped"), "true")
        XCTAssertEqual(response.header("x-refresh-skipped"), "true")
        XCTAssertNil(response.header("X-Missing"))
    }

    // `docs/api.md` shows "2026-09-16T08:00:00.000Z". JSONDecoder's built-in `.iso8601`
    // strategy REJECTS fractional seconds — decoding every snapshot would fail on a format
    // the server documents. Both spellings must decode.
    func testDecoderAcceptsFractionalAndWholeSeconds() throws {
        struct Stamped: Decodable { let at: Date }

        let withFraction = try SandboxJSON.decoder.decode(
            Stamped.self, from: Data(#"{"at":"2026-09-16T08:00:00.000Z"}"#.utf8))
        let withoutFraction = try SandboxJSON.decoder.decode(
            Stamped.self, from: Data(#"{"at":"2026-09-16T08:00:00Z"}"#.utf8))

        XCTAssertEqual(withFraction.at.timeIntervalSince1970, 1789545600, accuracy: 1)
        XCTAssertEqual(withFraction.at, withoutFraction.at)
    }

    func testDecoderRejectsNonsenseDateWithAClearMessage() {
        struct Stamped: Decodable { let at: Date }
        XCTAssertThrowsError(
            try SandboxJSON.decoder.decode(Stamped.self, from: Data(#"{"at":"not a date"}"#.utf8)))
    }

    func testMockRecordsRequestsAndReturnsStubs() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/healthz", status: 200, json: #"{"status":"ok","uptimeSeconds":12}"#)

        let response = try await mock.get(
            URL(string: "https://example.test/healthz")!, headers: ["X-Sandbox-Token": "abc"])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(mock.requests.count, 1)
        XCTAssertEqual(mock.requests[0].method, "GET")
        XCTAssertEqual(mock.requests[0].headers["X-Sandbox-Token"], "abc")
    }

    func testMockCanSimulateATransportFailure() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/healthz", message: "connection refused")
        do {
            _ = try await mock.get(URL(string: "https://example.test/healthz")!, headers: [:])
            XCTFail("expected a thrown transport failure")
        } catch {
            XCTAssertTrue("\(error)".contains("connection refused"))
        }
    }
}
