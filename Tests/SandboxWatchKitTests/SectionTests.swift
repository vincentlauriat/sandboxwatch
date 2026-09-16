import XCTest
@testable import SandboxWatchKit

final class SectionTests: XCTestCase {
    private func decode(_ json: String) throws -> Section<[String]> {
        try SandboxJSON.decoder.decode(Section<[String]>.self, from: Data(json.utf8))
    }

    func testOKCarriesItsPayloadAndDuration() throws {
        let section = try decode(#"{"status":"ok","data":["a","b"],"message":null,"durationMs":312}"#)
        XCTAssertTrue(section.isOK)
        XCTAssertEqual(section.durationMs, 312)
        XCTAssertEqual(section.fold(ok: { $0 }, unavailable: { _ in [] }), ["a", "b"])
    }

    // THE test of this project. If a denied section could be read as an empty collection, the
    // moment a Reader role is revoked the UI would announce that every role assignment
    // vanished — the exact false alarm AzureSandboxManager was built to prevent, and which it
    // guards with a test of its own. Here the payload is unreachable without the outcome, and
    // `fold` forces the caller to say what an unavailable section looks like.
    func testDeniedSectionYieldsAReasonAndNeverAPayload() throws {
        let section = try decode(#"{"status":"denied","data":null,"message":"AuthorizationFailed","durationMs":40}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertEqual(section.unavailableReason, "AuthorizationFailed")
        let rendered = section.fold(ok: { "\($0.count) items" }, unavailable: { "unavailable: \($0)" })
        XCTAssertEqual(rendered, "unavailable: AuthorizationFailed")
    }

    func testErrorSectionKeepsItsMessage() throws {
        let section = try decode(#"{"status":"error","data":null,"message":"ETIMEDOUT","durationMs":15000}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertEqual(section.unavailableReason, "ETIMEDOUT")
        XCTAssertEqual(section.durationMs, 15000)
    }

    func testUnavailableSectionWithoutAMessageStillExplainsItself() throws {
        let section = try decode(#"{"status":"denied","data":null,"message":null,"durationMs":5}"#)
        XCTAssertEqual(section.unavailableReason, "denied")
    }

    // `durationMs` is a sibling of `status` in the documented envelope, present on every
    // status. Keeping it only on `.ok` would make the contract model a partial one.
    func testDurationIsKeptOnEveryStatus() throws {
        XCTAssertEqual(try decode(#"{"status":"denied","data":null,"message":null,"durationMs":40}"#).durationMs, 40)
        XCTAssertEqual(try decode(#"{"status":"error","data":null,"message":null,"durationMs":9}"#).durationMs, 9)
    }

    // A status the client does not know is not a success. Defaulting it to `.ok` with no data
    // would be the empty-data bug arriving through a new server version.
    func testUnknownStatusIsTreatedAsUnavailable() throws {
        let section = try decode(#"{"status":"partial","data":["a"],"message":null,"durationMs":1}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertTrue(section.unavailableReason!.contains("partial"))
    }
}
