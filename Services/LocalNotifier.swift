import Foundation
import UserNotifications

/// Posts the app's local notifications.
///
/// Deliberately outside `ChatViewModel`: the message pipeline, the launch path
/// and the Settings self-test all drive this one code path, so a green test
/// button actually proves the same thing a real incoming message will do.
///
/// Everything is logged with a `🔔` prefix — macOS drops `print` output from a
/// normally-launched GUI app, so the useful diagnostics live behind the one
/// place that can be reproduced by running the binary from a terminal.
enum LocalNotifier {

    /// Latched for the session so the launch path and the sign-in path cannot
    /// both post the welcome notification.
    private(set) static var welcomeSent = false

    /// Authorization as the system currently reports it.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission while the status is still undecided and reports
    /// whether notifications may be shown afterwards. Never prompts twice —
    /// calling this on every launch must not nag the reader.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            log("denied by the system")
            return false
        case .notDetermined:
            break
        @unknown default:
            break
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            log(granted ? "✅ Notifications allowed" : "⚠️ Notifications denied")
            return granted
        } catch {
            log("❌ authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Posts a notification. Returns false when the system refused it — callers
    /// surface that instead of pretending the send succeeded.
    @discardableResult
    static func post(title: String, body: String, spaceId: String? = nil) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let spaceId {
            content.userInfo = ["spaceId": spaceId]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            log("posted \"\(title)\" — \(body.prefix(60))")
            return true
        } catch {
            log("❌ add() failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The startup notification, shown once per launch after permission is
    /// confirmed. No-op when it already fired or when notifications are off, so
    /// neither the launch path nor the sign-in path can duplicate it.
    static func sendWelcomeIfNeeded() async {
        guard !welcomeSent else { return }
        guard await requestAuthorization() else { return }
        welcomeSent = true
        await post(title: L.str("welcome.space"), body: L.str("welcome.message"))
    }

    /// One-shot diagnostic used by the Settings button: ensures permission and
    /// posts a notification the reader can see. Reports a human-readable reason
    /// when it fails instead of failing silently.
    static func runSelfTest() async -> String {
        let status = await authorizationStatus()
        if status == .denied {
            return L.str("settings.notify.test.denied")
        }
        guard await requestAuthorization() else {
            return L.str("settings.notify.test.denied")
        }
        let ok = await post(
            title: L.str("settings.notify.test.title"),
            body: L.str("settings.notify.test.body")
        )
        return ok
            ? L.str("settings.notify.test.ok")
            : L.str("settings.notify.test.failed", "system refused the request")
    }

    /// Localized one-line description of the current authorization status.
    static func statusDescription() async -> String {
        switch await authorizationStatus() {
        case .authorized: return L.str("settings.notify.status.granted")
        case .provisional: return L.str("settings.notify.status.provisional")
        case .ephemeral: return L.str("settings.notify.status.ephemeral")
        case .denied: return L.str("settings.notify.status.denied")
        case .notDetermined: return L.str("settings.notify.status.notdetermined")
        @unknown default: return L.str("settings.notify.status.unknown")
        }
    }

    private static func log(_ line: String) {
        print("🔔 \(line)")
    }
}
