import Foundation
import Yams

/// One watched sandbox. Deliberately holds no secret: the `SANDBOX_TOKEN` lives in the
/// Keychain (`TokenStore`). This is the one place SandboxWatch diverges from `hpm`'s
/// `fleet.yaml`, and it diverges because there the transport was SSH — not a secret — while
/// here the transport IS the secret.
public struct Sandbox: Codable, Equatable {
    public var name: String
    public var url: URL
    public var notes: String?

    public init(name: String, url: URL, notes: String? = nil) {
        self.name = name
        self.url = url
        self.notes = notes
    }
}

public struct Inventory: Codable, Equatable {
    public var sandboxes: [Sandbox]
    public init(sandboxes: [Sandbox] = []) { self.sandboxes = sandboxes }
}

public final class SandboxStore {
    public static let defaultPath = "~/.config/sbw/sandboxes.yaml"
    private let path: String

    public init(path: String = SandboxStore.defaultPath) {
        self.path = expandPath(path)
    }

    /// A missing file is an empty inventory, not an error: it is what a first run looks like.
    public func load() throws -> Inventory {
        guard FileManager.default.fileExists(atPath: path) else { return Inventory() }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        do {
            return try YAMLDecoder().decode(Inventory.self, from: contents)
        } catch {
            throw SandboxWatchError("cannot parse \(path): \(error)")
        }
    }

    public func save(_ inventory: Inventory) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(inventory)
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func add(_ sandbox: Sandbox) throws {
        var inventory = try load()
        guard !inventory.sandboxes.contains(where: { $0.name == sandbox.name }) else {
            throw SandboxWatchError("sandbox '\(sandbox.name)' already exists in \(path)")
        }
        inventory.sandboxes.append(sandbox)
        try save(inventory)
    }

    @discardableResult
    public func remove(named name: String) throws -> Bool {
        var inventory = try load()
        let before = inventory.sandboxes.count
        inventory.sandboxes.removeAll { $0.name == name }
        guard inventory.sandboxes.count != before else { return false }
        try save(inventory)
        return true
    }

    public func sandbox(named name: String) throws -> Sandbox {
        guard let found = try load().sandboxes.first(where: { $0.name == name }) else {
            throw SandboxWatchError(
                "unknown sandbox '\(name)' — declare it with: sbw sandbox add \(name) --url <url>")
        }
        return found
    }
}
