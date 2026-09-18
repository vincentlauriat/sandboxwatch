import AppKit
import SandboxWatchKit

// `AppDelegate` is @MainActor, and a top-level `main.swift` is not. `NSApplicationMain` is the
// AppKit-sanctioned entry point and runs on the main actor, so the delegate is built there.
@main
enum SandboxWatchApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
