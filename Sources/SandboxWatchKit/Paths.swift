import Foundation

/// Expands a leading `~` against the current user's home directory.
/// `expandingTildeInPath` lives on `NSString`, and everything else here works in `String`.
public func expandPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}
