import Foundation

/// Where each sandbox's last-seen change lives, so the CLI and the app agree on what has
/// already been reported.
public final class CursorStore {
    public static let defaultDirectory = "~/.config/sbw/cursors"
    private let directory: String

    public init(directory: String = CursorStore.defaultDirectory) {
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

    /// A missing or unreadable cursor is "no cursor": a fresh start, never a crash that
    /// blocks every command.
    public func mark(for sandbox: String) throws -> ChangeMark? {
        let path = try path(for: sandbox)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? SandboxJSON.decoder.decode(ChangeMark.self, from: data)
    }

    public func setMark(_ mark: ChangeMark, for sandbox: String) throws {
        let path = try path(for: sandbox)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        try encoder.encode(mark).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
