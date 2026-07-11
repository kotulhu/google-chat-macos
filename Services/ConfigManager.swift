import Foundation

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    private let clientIDKey = "googleClientID"
    private let reversedClientIDKey = "googleReversedClientID"
    private let displayNameKey = "localDisplayName"
    
    @Published var clientID: String {
        didSet {
            defaults.set(clientID, forKey: clientIDKey)
        }
    }

    @Published var reversedClientID: String {
        didSet {
            defaults.set(reversedClientID, forKey: reversedClientIDKey)
        }
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
        reversedClientID = defaults.string(forKey: reversedClientIDKey)
            ?? Self.bundleString(forKey: "GOOGLE_REVERSED_CLIENT_ID")
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
