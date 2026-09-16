import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class ScaffoldTests: XCTestCase {
    // The test target depends on an executable target carrying `@main`. That works, and
    // HomePortManager relies on it, but it is the one structural assumption in Package.swift —
    // exercise it in task 1 rather than discovering it wrong at task 12.
    func testTheCLITargetIsImportable() {
        XCTAssertEqual(SBW.configuration.commandName, "sbw")
    }

    func testErrorCarriesItsMessage() {
        let error = SandboxWatchError("unknown sandbox 'dev'")
        XCTAssertEqual(error.message, "unknown sandbox 'dev'")
        XCTAssertEqual(String(describing: error), "unknown sandbox 'dev'")
    }

    func testExpandPathExpandsLeadingTilde() {
        let expanded = expandPath("~/.config/sbw/sandboxes.yaml")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/.config/sbw/sandboxes.yaml"))
    }

    func testExpandPathLeavesAbsolutePathAlone() {
        XCTAssertEqual(expandPath("/tmp/sbw.yaml"), "/tmp/sbw.yaml")
    }
}
