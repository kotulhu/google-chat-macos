import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject private var config = ConfigManager.shared

    /// Current permission as reported by the system, refreshed when the window
    /// opens so a change made in System Settings is reflected immediately.
    @State private var notificationStatus = "…"
    /// Text of the last self-test result, shown once the button is pressed.
    @State private var testResult: String?
    @State private var isTesting = false

    /// The Settings window: editable OAuth client IDs, a local display name and
    /// a notification self-test, persisted through `ConfigManager`.
    var body: some View {
        Form {
            TextField("OAuth Client ID", text: $config.clientID)
                .textFieldStyle(.roundedBorder)

            TextField("Reversed Client ID", text: .constant(config.reversedClientID))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .help(L.str("settings.reversed.help"))
            
            TextField(L.str("display.name"), text: $config.localDisplayName)
                .textFieldStyle(.roundedBorder)
            
            Text(L.str("settings.oauth.note"))
                .font(.caption)
                .foregroundColor(.secondary)

            notificationSection
        }
        .padding()
        .frame(width: 480)
        .task { await refreshNotificationStatus() }
    }

    /// Permission readout plus a button that exercises the exact code path used
    /// for real incoming messages, so a failure here reproduces production.
    private var notificationSection: some View {
        Section(L.str("settings.notify.section")) {
            HStack {
                Text(L.str("settings.notify.status"))
                Spacer()
                Text(notificationStatus)
                    .foregroundColor(notificationStatusColor)
            }

            Button(L.str("settings.notify.test")) {
                runNotificationTest()
            }
            .disabled(isTesting)

            if isTesting {
                ProgressView().controlSize(.small)
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case L.str("settings.notify.status.granted"):
            return .green
        case L.str("settings.notify.status.denied"):
            return .red
        default:
            return .secondary
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await LocalNotifier.statusDescription()
    }

    private func runNotificationTest() {
        isTesting = true
        testResult = nil
        Task {
            let result = await LocalNotifier.runSelfTest()
            notificationStatus = await LocalNotifier.statusDescription()
            testResult = result
            isTesting = false
        }
    }
}
