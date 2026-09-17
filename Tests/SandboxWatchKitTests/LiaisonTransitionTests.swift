import XCTest
@testable import SandboxWatchKit

final class LiaisonTransitionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)
    private func later(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let healthy: Set<Doctor.Finding.Kind> = [.healthy]
    private let down: Set<Doctor.Finding.Kind> = [.unreachable]

    func testFirstObservationEstablishesAndAnnouncesNothing() {
        // Same rule as the change cursor's first run: declaring a sandbox must not replay its
        // history as an alarm.
        let decision = LiaisonMonitor.decide(observed: down, previous: nil, at: t0)

        XCTAssertNil(decision.transition)
        XCTAssertEqual(decision.state.confirmed, down)
        XCTAssertNil(decision.state.candidate)
    }

    func testAnUnchangedObservationIsSilent() {
        let first = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let second = LiaisonMonitor.decide(observed: healthy, previous: first, at: later(300))

        XCTAssertNil(second.transition)
        XCTAssertEqual(second.state.confirmed, healthy)
    }

    func testOneFailedReadingChangesNothing() {
        // A Mac that sleeps, changes Wi-Fi or switches to tethering manufactures spurious
        // "unreachable". One reading is not evidence.
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let second = LiaisonMonitor.decide(observed: down, previous: established, at: later(300))

        XCTAssertNil(second.transition)
        XCTAssertEqual(second.state.confirmed, healthy)
        XCTAssertEqual(second.state.candidate, down)
    }

    func testTwoConsecutiveReadingsChangeTheState() {
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let pending = LiaisonMonitor.decide(observed: down, previous: established, at: later(300)).state
        let third = LiaisonMonitor.decide(observed: down, previous: pending, at: later(600))

        XCTAssertEqual(third.transition, LiaisonTransition(from: healthy, to: down))
        XCTAssertEqual(third.state.confirmed, down)
        XCTAssertNil(third.state.candidate)
    }

    func testRecoveryAlsoNeedsTwoReadings() {
        // Both directions. Knowing it is over is worth as much as knowing it began — and a
        // single lucky reading is no more evidence than a single failed one.
        var state = LiaisonMonitor.decide(observed: down, previous: nil, at: t0).state
        state = LiaisonMonitor.decide(observed: healthy, previous: state, at: later(300)).state
        XCTAssertEqual(state.confirmed, down)

        let recovered = LiaisonMonitor.decide(observed: healthy, previous: state, at: later(600))
        XCTAssertEqual(recovered.transition, LiaisonTransition(from: down, to: healthy))
    }

    func testAThirdDifferentObservationReplacesTheCandidate() {
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let pending = LiaisonMonitor.decide(observed: down, previous: established, at: later(300)).state
        let other = LiaisonMonitor.decide(
            observed: [.unauthorised], previous: pending, at: later(600))

        XCTAssertNil(other.transition)
        XCTAssertEqual(other.state.confirmed, healthy)
        XCTAssertEqual(other.state.candidate, [.unauthorised])
    }

    func testALongGapReestablishesSilently() {
        // The lid was shut all weekend. The first reading on waking describes a state nobody
        // was watching, so it establishes rather than announces.
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let afterSleep = LiaisonMonitor.decide(observed: down, previous: established, at: later(3600))

        XCTAssertNil(afterSleep.transition)
        XCTAssertEqual(afterSleep.state.confirmed, down)
        XCTAssertNil(afterSleep.state.candidate)
    }

    func testAChangeOfSetIsATransitionEvenWhenTheWorstIsUnchanged() {
        // Doctor refuses to reduce its diagnosis to one verdict, so a transition is defined on
        // the set: {stale} -> {stale, sectionsUnavailable} is a real change.
        let one: Set<Doctor.Finding.Kind> = [.stale]
        let two: Set<Doctor.Finding.Kind> = [.stale, .sectionsUnavailable]

        var state = LiaisonMonitor.decide(observed: one, previous: nil, at: t0).state
        state = LiaisonMonitor.decide(observed: two, previous: state, at: later(300)).state
        let decision = LiaisonMonitor.decide(observed: two, previous: state, at: later(600))

        XCTAssertEqual(decision.transition, LiaisonTransition(from: one, to: two))
    }
}
