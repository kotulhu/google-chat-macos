import SwiftUI
import UserNotifications
import AppKit

struct SettingsView: View {
    @ObservedObject private var config = ConfigManager.shared

    /// Current permission as reported by the system, refreshed when the window
    /// opens so a change made in System Settings is reflected immediately.
    @State private var notificationStatus = "…"
    /// Text of the last self-test result, shown once the button is pressed.
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var selectedFeedElement = "text"

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

            feedFontSection
            notificationSection
        }
        .padding()
        .frame(width: 480)
        .task { await refreshNotificationStatus() }
    }

    private var feedFontSection: some View {
        Section(L.str("settings.font.section")) {
            Picker(L.str("settings.font.element"), selection: $selectedFeedElement) {
                ForEach(ConfigManager.feedFontElements, id: \.self) { element in
                    Text(feedFontElementTitle(element)).tag(element)
                }
            }
            .pickerStyle(.menu)

            Picker(L.str("settings.font.family"), selection: selectedFontFamily) {
                ForEach(availableFeedFontFamilies, id: \.self) { family in
                    Text(feedFontFamilyTitle(family)).tag(family)
                }
            }

            Picker(L.str("settings.font.size"), selection: selectedFontSize) {
                ForEach(ConfigManager.feedFontSizes, id: \.self) { size in
                    Text("\(Int(size)) pt").tag(size)
                }
            }

            Picker(L.str("settings.font.style"), selection: selectedFontStyle) {
                ForEach(ConfigManager.feedFontStyles, id: \.self) { style in
                    Text(feedFontStyleTitle(style)).tag(style)
                }
            }

            ColorPicker(L.str("settings.font.color"), selection: selectedFontColor)

            Button(L.str("settings.font.reset")) {
                config.resetFontSettings(for: selectedFeedElement)
            }
        }
    }

    private var availableFeedFontFamilies: [String] {
        var families = NSFontManager.shared.availableFontFamilies.sorted()
        if !families.contains("system") {
            families.insert("system", at: 0)
        }
        let selected = config.fontSettings(for: selectedFeedElement).family
        if !families.contains(selected) {
            families.append(selected)
        }
        return families
    }

    private var selectedFontFamily: Binding<String> {
        Binding(
            get: { config.fontSettings(for: selectedFeedElement).family },
            set: { value in
                var settings = config.fontSettings(for: selectedFeedElement)
                settings.family = value
                config.updateFontSettings(settings, for: selectedFeedElement)
            }
        )
    }

    private var selectedFontSize: Binding<Double> {
        Binding(
            get: { config.fontSettings(for: selectedFeedElement).size },
            set: { value in
                var settings = config.fontSettings(for: selectedFeedElement)
                settings.size = value
                config.updateFontSettings(settings, for: selectedFeedElement)
            }
        )
    }

    private var selectedFontStyle: Binding<String> {
        Binding(
            get: { config.fontSettings(for: selectedFeedElement).style },
            set: { value in
                var settings = config.fontSettings(for: selectedFeedElement)
                settings.style = value
                config.updateFontSettings(settings, for: selectedFeedElement)
            }
        )
    }

    private var selectedFontColor: Binding<Color> {
        Binding(
            get: {
                let value = config.fontSettings(for: selectedFeedElement).colorHex
                return value == "default" ? defaultColor(for: selectedFeedElement) : Color(feedHex: value)
            },
            set: { color in
                var settings = config.fontSettings(for: selectedFeedElement)
                settings.colorHex = color.feedHex
                config.updateFontSettings(settings, for: selectedFeedElement)
            }
        )
    }

    private func defaultColor(for element: String) -> Color {
        switch element {
        case "time", "sender": return Color(feedHex: "#8E8E93")
        case "link": return Color(feedHex: "#007AFF")
        default: return .primary
        }
    }

    private func feedFontElementTitle(_ element: String) -> String {
        switch element {
        case "time": return L.str("settings.font.element.time")
        case "sender": return L.str("settings.font.element.sender")
        case "text": return L.str("settings.font.element.text")
        case "link": return L.str("settings.font.element.link")
        default: return element
        }
    }

    private func feedFontFamilyTitle(_ family: String) -> String {
        switch family {
        case "system": return L.str("settings.font.family.system")
        case "SF Pro": return "SF Pro"
        case "Helvetica Neue": return "Helvetica Neue"
        case "Avenir Next": return "Avenir Next"
        case "Menlo": return "Menlo"
        case "Georgia": return "Georgia"
        default: return family
        }
    }

    private func feedFontStyleTitle(_ style: String) -> String {
        switch style {
        case "regular": return L.str("settings.font.style.regular")
        case "semibold": return L.str("settings.font.style.semibold")
        case "bold": return L.str("settings.font.style.bold")
        case "italic": return L.str("settings.font.style.italic")
        case "boldItalic": return L.str("settings.font.style.boldItalic")
        default: return style
        }
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
