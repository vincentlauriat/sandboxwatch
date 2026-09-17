import Foundation

/// What the last observations of one sandbox's link looked like.
///
/// `confirmed` is what has been announced. `candidate` is an observation seen once and not yet
/// believed — a Mac that sleeps, changes network or switches to tethering manufactures spurious
/// failures, and a repeated false alarm is exactly what makes an operator ignore the icon.
public struct LiaisonState: Codable, Equatable {
    public let confirmed: Set<Doctor.Finding.Kind>
    public let candidate: Set<Doctor.Finding.Kind>?
    public let observedAt: Date

    public init(confirmed: Set<Doctor.Finding.Kind>, candidate: Set<Doctor.Finding.Kind>?, observedAt: Date) {
        self.confirmed = confirmed
        self.candidate = candidate
        self.observedAt = observedAt
    }
}

public struct LiaisonTransition: Equatable {
    public let from: Set<Doctor.Finding.Kind>
    public let to: Set<Doctor.Finding.Kind>

    public init(from: Set<Doctor.Finding.Kind>, to: Set<Doctor.Finding.Kind>) {
        self.from = from
        self.to = to
    }
}

public struct LiaisonDecision: Equatable {
    public let state: LiaisonState
    public let transition: LiaisonTransition?
}

public enum LiaisonMonitor {
    /// Turns one observation into a transition, or into silence.
    ///
    /// Three safeguards, all of them here rather than in a caller:
    ///
    /// - the first observation establishes, it does not announce;
    /// - a change needs two consecutive readings, in both directions;
    /// - an observation older than `reestablishAfter` is treated as a fresh start, because
    ///   nobody was watching in between.
    public static func decide(
        observed: Set<Doctor.Finding.Kind>,
        previous: LiaisonState?,
        at now: Date,
        reestablishAfter: TimeInterval = 900
    ) -> LiaisonDecision {
        guard let previous, now.timeIntervalSince(previous.observedAt) <= reestablishAfter else {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: nil)
        }

        if observed == previous.confirmed {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: nil)
        }

        if observed == previous.candidate {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: LiaisonTransition(from: previous.confirmed, to: observed))
        }

        return LiaisonDecision(
            state: LiaisonState(confirmed: previous.confirmed, candidate: observed, observedAt: now),
            transition: nil)
    }
}
