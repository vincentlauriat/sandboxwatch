import ArgumentParser
import Foundation
import SandboxWatchKit

enum ReadCommands {
    /// `clientFor` is injected so tests never build a real `URLSessionHTTPClient`.
    static func status(
        sandboxes: [String],
        clientFor: (String) -> SandboxAPIClient
    ) async -> String {
        var rows: [StatusRow] = []
        for name in sandboxes {
            do {
                let response = try await clientFor(name).snapshot()
                rows.append(StatusRow.make(sandbox: name, response: response))
            } catch let failure as APIFailure {
                // One unreachable sandbox must not hide the others — `--all` is when you are
                // looking for the broken one.
                rows.append(StatusRow.unreachable(sandbox: name, failure: failure))
            } catch {
                rows.append(StatusRow.unreachable(sandbox: name, failure: .transport("\(error)")))
            }
        }

        var output = renderTable(rows)
        let problems = rows.compactMap { row in row.problem.map { "\(row.sandbox): \($0)" } }
        if !problems.isEmpty {
            output += "\n\n" + problems.joined(separator: "\n")
        }
        return output
    }

    static func doctor(sandbox: String, client: SandboxAPIClient) async -> String {
        let findings = await Doctor(client: client).diagnose()
        return findings.map { finding in
            let mark = finding.isProblem ? "!" : "."
            let step = finding.nextStep.map { "\n    → \($0)" } ?? ""
            return "[\(mark)] \(finding.headline)\(step)"
        }.joined(separator: "\n")
    }

    static func changes(
        sandbox: String,
        client: SandboxAPIClient,
        cursors: CursorStore,
        limit: Int,
        advance: Bool
    ) async throws -> String {
        let mark = try cursors.mark(for: sandbox)
        var currentLimit = limit
        var scan = ChangeCursor.scan(page: try await client.changes(limit: currentLimit), since: mark)

        // Widen and refetch while the page still has not reached back to the cursor.
        while scan.overflowed, let wider = ChangeCursor.nextLimit(after: currentLimit) {
            currentLimit = wider
            scan = ChangeCursor.scan(page: try await client.changes(limit: currentLimit), since: mark)
        }

        if advance, let newest = scan.newest {
            try cursors.setMark(newest, for: sandbox)
        }

        var lines: [String] = []
        if scan.overflowed {
            lines.append("! older events were not returned — the log moved by more than "
                       + "\(currentLimit) events since the last check, so some are missing here.")
            lines.append("")
        }

        if scan.newEvents.isEmpty {
            lines.append("nothing changed since the last check")
        } else {
            let formatter = ISO8601DateFormatter()
            for event in scan.newEvents {
                let flag: String
                switch event.severity {
                case .critical: flag = "!!"
                case .notable: flag = "!"
                case .informational: flag = " "
                }
                let detail = event.detail?["message"].map { " (\($0))" } ?? ""
                lines.append("\(flag) \(formatter.string(from: event.at))  \(event.type)  \(event.subject)\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ArgumentParser wrappers

/// Builds a real client for a declared sandbox. The only place the CLI touches the network
/// and the keychain.
func liveClient(for name: String) throws -> SandboxAPIClient {
    let sandbox = try SandboxStore().sandbox(named: name)
    let token = try requireToken(KeychainTokenStore(), for: name)
    return SandboxAPIClient(baseURL: sandbox.url, token: token, http: URLSessionHTTPClient())
}

func resolveNames(_ name: String?, all: Bool) throws -> [String] {
    if all { return try SandboxStore().load().sandboxes.map(\.name) }
    guard let name else {
        throw SandboxWatchError("name a sandbox, or pass --all")
    }
    return [name]
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Snapshot age, apps, budget and collector state.")

    @Argument var name: String?
    @Flag(name: .long, help: "Every declared sandbox.") var all = false

    func run() async throws {
        let names = try resolveNames(name, all: all)
        // `liveClient` throws for an unknown sandbox or a missing token; resolve them all
        // first so the table is not half-printed before failing.
        var clients: [String: SandboxAPIClient] = [:]
        for name in names { clients[name] = try liveClient(for: name) }
        print(await ReadCommands.status(sandboxes: names) { clients[$0]! })
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Tell apart an outage, a refused token and a role that has not propagated.")

    @Argument var name: String

    func run() async throws {
        print(await ReadCommands.doctor(sandbox: name, client: try liveClient(for: name)))
    }
}

struct ChangesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "changes", abstract: "What changed since the last check.")

    @Argument var name: String
    @Option(help: "How many events to ask for (1–500).") var limit = SandboxAPI.defaultChangeLimit
    @Flag(name: .long, help: "Do not move the cursor — show the same events again next time.")
    var keepCursor = false

    func run() async throws {
        print(try await ReadCommands.changes(
            sandbox: name, client: try liveClient(for: name), cursors: CursorStore(),
            limit: limit, advance: !keepCursor))
    }
}
