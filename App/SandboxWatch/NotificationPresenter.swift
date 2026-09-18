import Foundation
import UserNotifications
import SandboxWatchKit

/// Turns a Kit `Alert` into a delivered notification, and keeps the authorization status where the
/// menu can show it.
///
/// Measured 2026-09-18 on this Mac: `requestAuthorization` came back `granted=false` with
/// `authorizationStatus` already `denied`, without a prompt, for a bundle identifier never seen
/// before — so authorization is a runtime condition, not something to assume.
@MainActor
final class NotificationPresenter {
    private(set) var isRefused = false

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            isRefused = !granted
        } catch {
            isRefused = true
        }
    }

    func deliver(_ alert: WatchPresentation.Alert) async {
        guard !isRefused else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = alert.severity == .critical ? .default : nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
