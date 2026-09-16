import Foundation

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    private let clientIDKey = "googleClientID"
    private let displayNameKey = "localDisplayName"
    
    @Published var clientID: String {
        didSet {
            defaults.set(clientID, forKey: clientIDKey)
        }
    }

    /// Derives the Google OAuth callback URL scheme (reversed client ID) from
    /// the regular client ID by reversing its dot-separated components:
    /// `<prefix>.apps.googleusercontent.com` → `com.googleusercontent.apps.<prefix>`.
    /// The Sign-In SDK and the build-time URL scheme both expect this exact
    /// form, so the value is never stored — it is always recomputed.
    var reversedClientID: String {
        clientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .reversed()
            .map(String.init)
            .joined(separator: ".")
    }
    
    @Published var localDisplayName: String {
        didSet {
            defaults.set(localDisplayName, forKey: displayNameKey)
            NotificationCenter.default.post(name: Self.localDisplayNameDidChangeNotification, object: nil)
        }
    }
    
    private init() {
        clientID = defaults.string(forKey: clientIDKey)
            ?? Self.bundleString(forKey: "GOOGLE_CLIENT_ID")
            ?? ""
        localDisplayName = defaults.string(forKey: displayNameKey) ?? ""
    }

    private static func bundleString(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
    
    static let localDisplayNameDidChangeNotification = Notification.Name("ConfigManagerLocalDisplayNameDidChange")
}
