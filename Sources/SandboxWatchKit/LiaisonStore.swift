import Foundation

/// Where each sandbox's last-observed link state lives, so `sbw watch` and the app agree on
/// what has already been announced — the same arrangement as `CursorStore`.
public final class LiaisonStore {
    public static let defaultDirectory = "~/.config/sbw/liaison"
    private let directory: String

    public init(directory: String = LiaisonStore.defaultDirectory) {
        self.directory = expandPath(directory)
    }

    private func path(for sandbox: String) throws -> String {
        // A sandbox name comes from the command line; letting it act as a path would write
        // outside this directory.
        guard !sandbox.isEmpty, !sandbox.contains("/"), sandbox != ".", sandbox != ".." else {
            throw SandboxWatchError("invalid sandbox name '\(sandbox)'")
        }
        return directory + "/" + sandbox + ".json"
    }

    /// A missing or unreadable file is "no state": a fresh start, never a crash that blocks
    /// every command.
    public func state(for sandbox: String) throws -> LiaisonState? {
        let path = try path(for: sandbox)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? SandboxJSON.decoder.decode(LiaisonState.self, from: data)
    }

    public func setState(_ state: LiaisonState, for sandbox: String) throws {
        let path = try path(for: sandbox)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        try encoder.encode(state).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
