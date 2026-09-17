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
    public let appCount: Int?
    public let status: String?
}

public struct AzureApp: Decodable, Equatable {
    public let name: String
    public let state: String?
    public let runtime: String?
    public let httpsOnly: Bool?
    public let url: String?

    public var isRunning: Bool { state?.caseInsensitiveCompare("Running") == .orderedSame }
}

public struct Budget: Decodable, Equatable {
    public let amount: Double?
    public let spend: Double?
    public let percentage: Double?
    public let thresholds: [Double]?
}

public struct RoleAssignment: Decodable, Equatable {
    public let principalId: String?
    public let roleDefinitionName: String?
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
    public let name: String
    public let url: String?
    public let statusCode: Int?
    public let latencyMs: Double?

    /// A probe with no status code did not answer at all.
    public var answered: Bool { statusCode != nil }
}

public struct Snapshot: Decodable {
    public let identity: Identity
    public let resources: Section<[AzureResource]>
    public let plans: Section<[ServicePlan]>
    public let apps: Section<[AzureApp]>
    public let budget: Section<Budget>
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
