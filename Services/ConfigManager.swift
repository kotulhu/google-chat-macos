import Foundation

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    private let clientIDKey = "googleClientID"
    private let displayNameKey = "localDisplayName"
    private let pinnedSpaceIdsKey = "pinnedSpaceIds"
    
    @Published var clientID: String {
        didSet {
            defaults.set(clientID, forKey: clientIDKey)
        }
    }

    /// IDs of pinned chats in their stable display order (order of pinning:
    /// the first pinned chat stays on top, new pins are appended).
    @Published var pinnedSpaceIds: [String] {
        didSet {
            defaults.set(pinnedSpaceIds, forKey: pinnedSpaceIdsKey)
        }
    }

    /// Returns whether the given chat is pinned.
    func isPinned(_ spaceId: String) -> Bool {
        pinnedSpaceIds.contains(spaceId)
    }

    /// Pins a chat (appended to the top group) or unpins it when already pinned.
    func togglePin(_ spaceId: String) {
        if pinnedSpaceIds.contains(spaceId) {
            pinnedSpaceIds.removeAll { $0 == spaceId }
        } else {
            pinnedSpaceIds.append(spaceId)
        }
    }

    /// Drops a chat from the pinned list (e.g. after leaving it).
    func removePin(_ spaceId: String) {
        pinnedSpaceIds.removeAll { $0 == spaceId }
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
        pinnedSpaceIds = defaults.stringArray(forKey: pinnedSpaceIdsKey) ?? []
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
