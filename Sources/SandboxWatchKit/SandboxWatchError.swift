import Foundation

/// The Kit's only thrown error: conditions the operator caused and can fix — an unknown
/// sandbox name, an unparseable inventory file.
///
/// States the server or the network can legitimately be in are NOT errors here. A denied
/// collector, a server with no snapshot yet, a stale snapshot: those are values the UI
/// displays (`Section`, `APIFailure`, `Doctor.Finding`). Throwing them would turn an ordinary
/// state into a failure, which is the mistake this project exists to avoid.
public struct SandboxWatchError: Error, CustomStringConvertible, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}
