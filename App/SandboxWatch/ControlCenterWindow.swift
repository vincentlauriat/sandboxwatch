import AppKit
import SwiftUI
import SandboxWatchKit

/// The control center window, owned by the menu bar agent.
///
/// Two things the 2026-09-18 spike established, both of which look like bugs if you get them wrong:
/// an `LSUIElement` app has **no main menu**, so Cmd-W and Cmd-Q simply do not exist until one is
/// built by hand; and the menu must exist *before* `setActivationPolicy(.regular)`, or the first
/// activation shows an empty menu bar. The status item survives both policy flips — measured,
/// because losing it is the obvious way this goes wrong.
@MainActor
final class ControlCenterWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// One window, reused. A second click on the menu item raises the one that exists.
    func show(_ content: ControlCenterView) {
        if let window {
            activate(window)
            return
        }

        installMenuIfNeeded()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "SandboxWatch")
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.setFrameAutosaveName("ControlCenter")
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        activate(window)
    }

    /// A poll finished while the window is open. Only replace the contents if there is a window;
    /// building one here would pop it open behind the operator's back.
    func update(_ content: ControlCenterView) {
        guard window != nil else { return }
        window?.contentView = NSHostingView(rootView: content)
    }

    private func activate(_ window: NSWindow) {
        // One runloop turn after the policy change. Activating before the window server has
        // acknowledged it leaves the window visible but not key — open, and impossible to type in.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Back to an agent. Staying `.regular` would leave a dock icon and a menu bar for an app
        // with no window.
        NSApp.setActivationPolicy(.accessory)
    }

    private func installMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: String(localized: "Close"),
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: String(localized: "Quit SandboxWatch"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
