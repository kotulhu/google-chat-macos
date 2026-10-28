import Foundation

struct FeedFontSettings: Codable, Equatable {
    var family: String
    var size: Double
    var style: String
    var colorHex: String

    init(family: String, size: Double, style: String, colorHex: String = "default") {
        self.family = family
        self.size = size
        self.style = style
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case family, size, style, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decode(String.self, forKey: .family)
        size = try container.decode(Double.self, forKey: .size)
        style = try container.decode(String.self, forKey: .style)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "default"
    }
}

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    private let clientIDKey = "googleClientID"
    private let displayNameKey = "localDisplayName"
    private let pinnedSpaceIdsKey = "pinnedSpaceIds"
    private let feedFontFamilyKey = "feedFontFamily"
    private let feedFontSizeKey = "feedFontSize"
    private let feedFontStyleKey = "feedFontStyle"
    private let feedFontSettingsKey = "feedFontSettings"

    static let feedFontFamilies = [
        "system", "SF Pro", "Helvetica Neue", "Avenir Next", "Menlo", "Georgia"
    ]
    static let feedFontSizes: [Double] = [12, 14, 16, 18, 20, 22, 24]
    static let feedFontStyles = ["regular", "semibold", "bold", "italic", "boldItalic"]
    static let feedFontElements = ["time", "sender", "text", "link", "quote"]
    
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

    @Published private(set) var feedFontSettings: [String: FeedFontSettings] {
        didSet {
            guard let data = try? JSONEncoder().encode(feedFontSettings) else { return }
            defaults.set(data, forKey: feedFontSettingsKey)
        }
    }

    func fontSettings(for element: String) -> FeedFontSettings {
        feedFontSettings[element] ?? Self.defaultFeedFontSettings(for: element)
    }

    func updateFontSettings(_ settings: FeedFontSettings, for element: String) {
        feedFontSettings[element] = settings
    }

    func resetFontSettings(for element: String) {
        feedFontSettings[element] = Self.defaultFeedFontSettings(for: element)
    }
    
    private init() {
        clientID = defaults.string(forKey: clientIDKey)
            ?? Self.bundleString(forKey: "GOOGLE_CLIENT_ID")
            ?? ""
        localDisplayName = defaults.string(forKey: displayNameKey) ?? ""
        pinnedSpaceIds = defaults.stringArray(forKey: pinnedSpaceIdsKey) ?? []

        let legacyFamily = defaults.string(forKey: feedFontFamilyKey) ?? "system"
        let legacySize = defaults.double(forKey: feedFontSizeKey)
        let legacyStyle = defaults.string(forKey: feedFontStyleKey) ?? "regular"
        let legacySettings = FeedFontSettings(
            family: legacyFamily,
            size: legacySize > 0 ? legacySize : 16,
            style: legacyStyle
        )

        let storedSettings = defaults.data(forKey: feedFontSettingsKey)
            .flatMap { try? JSONDecoder().decode([String: FeedFontSettings].self, from: $0) }
        var loadedSettings = storedSettings ?? [:]
        for element in Self.feedFontElements where loadedSettings[element] == nil {
            var migrated = Self.defaultFeedFontSettings(for: element)
            migrated.family = legacySettings.family
            migrated.size = legacySettings.size
            migrated.style = legacySettings.style
            loadedSettings[element] = migrated
        }
        feedFontSettings = loadedSettings
    }

    private static func defaultFeedFontSettings(for element: String) -> FeedFontSettings {
        switch element {
        case "time", "sender":
            return FeedFontSettings(family: "system", size: 12, style: "regular", colorHex: "#8E8E93")
        case "link":
            return FeedFontSettings(family: "system", size: 16, style: "regular", colorHex: "#007AFF")
        case "quote":
            return FeedFontSettings(family: "system", size: 14, style: "italic", colorHex: "#8E8E93")
        default:
            return FeedFontSettings(family: "system", size: 16, style: "regular")
        }
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
