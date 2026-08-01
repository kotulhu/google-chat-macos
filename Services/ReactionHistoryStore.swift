import Foundation
import Combine

@MainActor
final class ReactionHistoryStore: ObservableObject {
    static let shared = ReactionHistoryStore()
    
    static let defaultPopularEmojis: [String] = [
        "👍", "❤️", "😂", "😮", "😢", "🙏", "🔥", "🎉", "💯", "✅",
        "👀", "🚀", "🤔", "😍", "🤯"
    ]
    
    @Published private(set) var recentEmojis: [String]
    
    private var usageCounts: [String: Int]
    private let defaults = UserDefaults.standard
    private let key = "recentReactionEmojis"
    private let countsKey = "reactionUsageCounts"
    private let limit = 15
    
    private init() {
        recentEmojis = defaults.stringArray(forKey: key) ?? []
        usageCounts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }
    
    var menuEmojis: [String] {
        var merged = recentEmojis
        for emoji in Self.defaultPopularEmojis where !merged.contains(emoji) {
            merged.append(emoji)
        }
        if merged.count > limit {
            merged = Array(merged.prefix(limit))
        }
        return merged.sorted { a, b in
            let ca = usageCounts[a] ?? 0
            let cb = usageCounts[b] ?? 0
            if ca != cb { return ca > cb }
            let ia = recentEmojis.firstIndex(of: a) ?? Int.max
            let ib = recentEmojis.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }
    
    func record(_ emoji: String) {
        var updated = recentEmojis.filter { $0 != emoji }
        updated.insert(emoji, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        recentEmojis = updated
        usageCounts[emoji, default: 0] += 1
        defaults.set(updated, forKey: key)
        defaults.set(usageCounts, forKey: countsKey)
    }
}
