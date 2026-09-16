import Foundation

/// Separates the states an operator confuses at the worst moment. The project the server was
/// written after began with half an hour spent on wrong readings — "the subscription was
/// deleted", "the tenant moved" — when the truth was a role assignment that had moved.
public struct Doctor {
    public enum Finding: Equatable {
        case unreachable(String)
        case unauthorised
        case notCollectedYet
        case serverProblem(String)
        case stale(ageSeconds: Double)
        case sectionsUnavailable([String])
        case healthy(ageSeconds: Double)

        public var isProblem: Bool {
            if case .healthy = self { return false }
            return true
        }

        public var headline: String {
            switch self {
            case .unreachable(let detail):
                return "the app could not be reached (\(detail))"
            case .unauthorised:
                return "the token was refused"
            case .notCollectedYet:
                return "the app is up but has not completed a collection yet"
            case .serverProblem(let detail):
                return "the server reported a failure: \(detail)"
            case .stale(let age):
                return "the snapshot is \(Int(age / 60)) minutes old"
            case .sectionsUnavailable(let names):
                return "these sections did not collect: \(names.joined(separator: ", "))"
            case .healthy(let age):
                return "everything collected, \(Int(age)) seconds ago"
            }
        }

        public var nextStep: String? {
            switch self {
            case .unreachable:
                return "check the URL in the inventory, and that the web app is running"
            case .unauthorised:
                return "set the token again: sbw sandbox add <name> --url <url>"
            case .notCollectedYet:
                return "wait for the next collection — do not redeploy, the app is working"
            case .serverProblem:
                return "check the web app's log stream in Azure"
            case .stale:
                return "the collector has stalled; check the app's log stream"
            case .sectionsUnavailable:
                return "grant Reader on the resource group to the app's managed identity — "
                     + "and if you just granted it, wait: role membership is cached and Microsoft "
                     + "documents up to 24 hours before it takes effect. This is not a failure."
            case .healthy:
                return nil
            }
        }
    }

    private let client: SandboxAPIClient
    private let staleAfterSeconds: Double

    /// Default threshold: three times the server's default ten-minute interval. The API does
    /// not expose the configured interval, so this is a decision, not a reading.
    public init(client: SandboxAPIClient, staleAfterSeconds: Double = 1800) {
        self.client = client
        self.staleAfterSeconds = staleAfterSeconds
    }

    /// Always non-empty, most important first. Several findings can be true at once — a stale
    /// snapshot that also shows denied sections — and reducing that to one verdict would hide
    /// whichever the operator needed.
    public func diagnose() async -> [Finding] {
        let response: SnapshotResponse
        do {
            response = try await client.snapshot()
        } catch let failure as APIFailure {
            switch failure {
            case .transport(let detail):    return [.unreachable(detail)]
            case .unauthorised:             return [.unauthorised]
            case .noSnapshot:               return [.notCollectedYet]
            case .notFound:                 return [.serverProblem(failure.explanation)]
            case .serverError, .unexpected: return [.serverProblem(failure.explanation)]
            case .malformed(let detail):    return [.serverProblem("malformed response: \(detail)")]
            }
        } catch {
            return [.unreachable("\(error)")]
        }

        var findings: [Finding] = []

        // Staleness first: a two-hour-old reading of "denied" may describe a state that no
        // longer exists, so the age has to be known before the sections are believed.
        if response.ageSeconds > staleAfterSeconds {
            findings.append(.stale(ageSeconds: response.ageSeconds))
        }

        let unavailable = response.snapshot.unavailableSections
        if !unavailable.isEmpty {
            findings.append(.sectionsUnavailable(unavailable))
        }

        if findings.isEmpty {
            findings.append(.healthy(ageSeconds: response.ageSeconds))
        }
        return findings
    }
}
