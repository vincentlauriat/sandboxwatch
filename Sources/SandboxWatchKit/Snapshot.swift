import Foundation

/// Which scope a snapshot describes. Deliberately **not** a `Section`: this is the server's own
/// configuration, it is known before any collector runs, and it can never be denied. Modelling it
/// as a section — as this client did for the whole of batch 1 — makes every real snapshot fail to
/// decode, because the wire has no `status` key here.
///
/// `subscriptionId` is what a write action compares against the subscription `az` is pointed at.
public struct Identity: Decodable, Equatable {
    public let available: Bool
    public let subscriptionId: String
    public let resourceGroup: String
}

public struct AzureResource: Decodable, Equatable {
    public let name: String
    public let type: String
    public let location: String
}

public struct ServicePlan: Decodable, Equatable {
    public let name: String
    public let tier: String?
    public let size: String?
    /// The wire calls this `sites`. It was modelled as `appCount` and therefore always decoded
    /// to nil — a silent wrong answer rather than a failure.
    public let sites: Int?
    public let status: String?
    public let location: String?
}

public struct AzureApp: Decodable, Equatable {
    public let name: String
    public let state: String?
    public let plan: String?
    public let runtime: String?
    public let httpsOnly: Bool?
    public let alwaysOn: Bool?
    public let url: String?
    public let location: String?

    public var isRunning: Bool { state?.caseInsensitiveCompare("Running") == .orderedSame }
}

/// One budget. The wire sends a **list** — a resource group can carry several — and names the
/// fields `spent` and `percent`. The model said one object with `spend` and `percentage`.
public struct Budget: Decodable, Equatable {
    public let name: String?
    public let amount: Double?
    public let currency: String?
    public let spent: Double?
    public let percent: Double?
    public let timeGrain: String?
    public let thresholds: [Double]?
}

public struct RoleAssignment: Decodable, Equatable {
    public let id: String?
    public let principalId: String?
    public let principalType: String?
    /// The wire sends the role definition **id**, not its display name. Resolving a name would
    /// need directory access this identity does not have.
    public let roleDefinitionId: String?
    public let scope: String?
}

public struct ResourceLock: Decodable, Equatable {
    public let name: String?
    public let level: String?
}

public struct Governance: Decodable, Equatable {
    public let roleAssignments: [RoleAssignment]?
    public let locks: [ResourceLock]?
    public let denyAssignments: [String]?
}

public struct Probe: Decodable, Equatable {
    /// The wire calls this `app`, and it is required — modelling it as `name` made every
    /// snapshot with probes fail to decode.
    public let app: String
    public let url: String?
    public let httpStatus: Int?
    public let latencyMs: Double?
    public let error: String?

    /// A probe with no status code did not answer at all.
    public var answered: Bool { httpStatus != nil }
}

public struct Snapshot: Decodable {
    public let identity: Identity
    public let resources: Section<[AzureResource]>
    public let plans: Section<[ServicePlan]>
    public let apps: Section<[AzureApp]>
    public let budget: Section<[Budget]>
    public let governance: Section<Governance>
    public let probes: Section<[Probe]>

    /// The sections that did not collect, by name — what `doctor` reports and what the UI
    /// must explain rather than render as empty.
    public var unavailableSections: [String] {
        // `identity` is absent on purpose: it is configuration, not a collection, so it has
        // no unavailable state to report.
        var names: [String] = []
        if !resources.isOK { names.append("resources") }
        if !plans.isOK { names.append("plans") }
        if !apps.isOK { names.append("apps") }
        if !budget.isOK { names.append("budget") }
        if !governance.isOK { names.append("governance") }
        if !probes.isOK { names.append("probes") }
        return names
    }
}

public struct SnapshotResponse: Decodable {
    public let collectedAt: Date
    public let ageSeconds: Double
    public let snapshot: Snapshot
}

public struct AppsResponse: Decodable {
    public let collectedAt: Date
    public let ageSeconds: Double
    public let apps: Section<[AzureApp]>
    public let probes: Section<[Probe]>
}
