import ArgumentParser
import Foundation
import SandboxWatchKit

/// Reads one line with terminal echo off, so the token is not left on screen — and falls back
/// to a plain read when stdin is not a terminal (a pipe, a test, CI), where there is no echo
/// to disable. `readLine()` alone would echo: never promise otherwise in the prompt.
func readSecretLine() -> String? {
    guard isatty(STDIN_FILENO) == 1 else { return readLine(strippingNewline: true) }

    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else { return readLine(strippingNewline: true) }
    var quiet = original
    quiet.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &quiet)
    defer {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        FileHandle.standardError.write(Data("\n".utf8))
    }
    return readLine(strippingNewline: true)
}

/// The decisions behind `sbw sandbox …`, separated from ArgumentParser so they can be tested
/// without spawning a process.
enum SandboxAdmin {
    static func add(
        name: String, url: String, notes: String?, token: String,
        store: SandboxStore, tokens: TokenStore
    ) throws -> String {
        guard let parsed = URL(string: url), parsed.host != nil else {
            throw SandboxWatchError("'\(url)' is not a URL")
        }
        // The dashboard exposes infrastructure detail and the token travels in the header.
        // Over plain HTTP both are readable by anyone on the path.
        guard parsed.scheme?.lowercased() == "https" else {
            throw SandboxWatchError("the URL must be https — '\(url)' is not")
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SandboxWatchError("the token is empty")
        }

        // Reject a duplicate name before writing anything. Discovering it after the token is
        // written would mean undoing that write — and the token now sitting there belongs to
        // the sandbox that already exists, so "undo" would destroy working configuration.
        guard try !store.load().sandboxes.contains(where: { $0.name == name }) else {
            throw SandboxWatchError("sandbox '\(name)' already exists — remove it first, or pick another name")
        }

        // The token goes in first: the other order leaves the inventory holding a sandbox with
        // no token when the keychain write fails, and the repair the operator is then told to
        // run — `sbw sandbox add <name>` — would fail with "already exists".
        //
        // The rollback restores what was there rather than deleting, so a failure here can
        // never leave the keychain emptier than it found it.
        let previous = try tokens.token(for: name)
        try tokens.setToken(trimmed, for: name)
        do {
            try store.add(Sandbox(name: name, url: parsed, notes: notes))
        } catch {
            if let previous {
                try? tokens.setToken(previous, for: name)
            } else {
                try? tokens.removeToken(for: name)
            }
            throw error
        }
        return "added '\(name)' (\(parsed.absoluteString)); token stored in the keychain"
    }

    static func list(store: SandboxStore) throws -> String {
        let sandboxes = try store.load().sandboxes
        guard !sandboxes.isEmpty else {
            return "no sandbox declared — add one with: sbw sandbox add <name> --url <https url>"
        }
        return sandboxes.map { sandbox in
            let notes = sandbox.notes.map { "  — \($0)" } ?? ""
            return "\(sandbox.name)  \(sandbox.url.absoluteString)\(notes)"
        }.joined(separator: "\n")
    }

    static func remove(name: String, store: SandboxStore, tokens: TokenStore) throws -> String {
        guard try store.remove(named: name) else {
            throw SandboxWatchError("unknown sandbox '\(name)'")
        }
        // The token outlives nothing: a keychain entry for a sandbox that no longer exists
        // would never be cleaned up by anything else.
        try tokens.removeToken(for: name)
        return "removed '\(name)' and its token"
    }
}

struct SandboxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sandbox",
        abstract: "Declare the sandboxes to watch.",
        subcommands: [Add.self, List.self, Remove.self])

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a sandbox. The token is read from stdin, never from an argument.")

        @Argument(help: "A short name for this sandbox.") var name: String
        @Option(help: "The https base URL of the Azure Sandbox Manager app.") var url: String
        @Option(help: "A free-text note.") var notes: String?

        func run() throws {
            // An argument would land in the shell history and in the process table, where
            // anyone on the machine can read it. stdin keeps it out of both.
            FileHandle.standardError.write(Data("Token for '\(name)': ".utf8))
            guard let token = readSecretLine() else {
                throw SandboxWatchError("no token read from stdin")
            }
            print(try SandboxAdmin.add(name: name, url: url, notes: notes, token: token,
                                       store: SandboxStore(), tokens: KeychainTokenStore()))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the declared sandboxes.")

        func run() throws {
            print(try SandboxAdmin.list(store: SandboxStore()))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a sandbox and its token.")

        @Argument var name: String

        func run() throws {
            print(try SandboxAdmin.remove(name: name, store: SandboxStore(), tokens: KeychainTokenStore()))
        }
    }
}
