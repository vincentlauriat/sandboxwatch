import AppKit
import SandboxWatchKit

/// The menu bar agent.
///
/// It owns nothing worth asserting: the Kit decides what a report means (`WatchPresentation`),
/// how to read one (`SandboxWatcher.poll`), and what the sandbox said (`Doctor`). What is left
/// here is an `NSStatusItem`, a timer, and the wiring between them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Five minutes. Long enough that the sandbox is not polled for nothing, short enough that a
    /// transition is seen while the memory of what changed is still fresh.
    private static let interval: TimeInterval = 300

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = SandboxStore()
    private let tokens = KeychainTokenStore()
    private let notifications = NotificationPresenter()

    /// Per-surface state, the amendment of 2026-09-18 to §6.3 of the spec. The liaison store
    /// matters as much as the cursor: `poll` persists its decision unconditionally, so sharing
    /// `liaison/` with `sbw watch` would let whichever polled first confirm the state, and the
    /// other would see no transition and stay silent.
    private let cursors = CursorStore(directory: "~/.config/sbw/cursors-app")
    private let liaison = LiaisonStore(directory: "~/.config/sbw/liaison-app")

    private var timer: Timer?
    private var lines: [(sandbox: String, headline: String, icon: WatchPresentation.StatusIcon)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        show(icon: .healthy, checking: true)
        Task { await notifications.requestAuthorization() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollAll() }
        }
        Task { await pollAll() }
    }

    // MARK: - Polling

    private func pollAll() async {
        let sandboxes = (try? store.load().sandboxes) ?? []
        var results: [(String, String, WatchPresentation.StatusIcon)] = []

        for sandbox in sandboxes {
            guard let token = (try? tokens.token(for: sandbox.name)) ?? nil else {
                results.append((sandbox.name, String(localized: "no token in the Keychain"), .unreachable))
                continue
            }
            let client = SandboxAPIClient(
                baseURL: sandbox.url, token: token, http: URLSessionHTTPClient())

            do {
                let report = try await SandboxWatcher.poll(
                    sandbox: sandbox.name, client: client, liaison: liaison, cursors: cursors)

                for alert in WatchPresentation.alerts(for: report, sandbox: sandbox.name) {
                    await notifications.deliver(alert)
                }
                let headline = report.findings.map(\.headline).joined(separator: "; ")
                results.append((sandbox.name, headline, WatchPresentation.icon(for: report)))
            } catch {
                results.append((sandbox.name, error.localizedDescription, .unreachable))
            }
        }

        lines = results
        show(icon: worst(of: results.map(\.2)), checking: false)
    }

    /// One icon for several sandboxes: the worst state wins. Averaging would hide the dead one,
    /// which is the only one you are looking for.
    private func worst(of icons: [WatchPresentation.StatusIcon]) -> WatchPresentation.StatusIcon {
        if icons.contains(.unreachable) { return .unreachable }
        if icons.contains(.degraded) { return .degraded }
        return .healthy
    }

    // MARK: - The menu bar

    private func show(icon: WatchPresentation.StatusIcon, checking: Bool) {
        let symbol: String
        switch icon {
        case .healthy:     symbol = "checkmark.circle"
        case .degraded:    symbol = "exclamationmark.triangle"
        case .unreachable: symbol = "xmark.octagon"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: icon.rawValue)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = buildMenu(checking: checking)
    }

    private func buildMenu(checking: Bool) -> NSMenu {
        let menu = NSMenu()

        if checking {
            menu.addItem(disabled(String(localized: "Checking…")))
        } else if lines.isEmpty {
            menu.addItem(disabled(String(localized: "No sandbox declared — run sbw sandbox add")))
        } else {
            for line in lines {
                menu.addItem(disabled("\(line.sandbox) — \(line.headline)"))
            }
        }

        // An agent with no dock icon that silently fails to notify is indistinguishable from a
        // sandbox that is fine. Say so rather than let the silence mean two things.
        if notifications.isRefused {
            menu.addItem(.separator())
            let item = NSMenuItem(
                title: String(localized: "Notifications refused — open Settings"),
                action: #selector(openNotificationSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(
            title: String(localized: "Refresh now"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit SandboxWatch"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshNow() {
        show(icon: worst(of: lines.map(\.icon)), checking: true)
        Task { await pollAll() }
    }

    @objc private func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
