import Foundation

/// Status of a scheduled message entry in the local queue.
enum ScheduledMessageStatus: String, Codable {
    case pending
    case overdue
}

/// A message composed for later sending, persisted locally so it survives app
/// restarts. There is at most one entry per space.
struct ScheduledMessage: Identifiable, Equatable, Codable {
    var id: String
    var spaceId: String
    var text: String
    var attachmentFileURLs: [String] = []
    var quotedMessageId: String?
    var quotedLastUpdateTime: String?
    var scheduledAt: Date
    var status: ScheduledMessageStatus
}

/// Local, on-disk queue of scheduled messages (one per space), deliberately
/// kept separate from the sent/cached message storage. Follows the pattern of
/// `ReactionHistoryStore`: a small `@MainActor` singleton persisted through
/// `UserDefaults` as JSON, publishing changes so open chats re-render.
@MainActor
final class ScheduledMessageStore: ObservableObject {
    static let shared = ScheduledMessageStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "scheduledMessages"

    @Published private(set) var entries: [String: ScheduledMessage] = [:]

    private init() {
        load()
    }

    /// The scheduled message of a space (any status), or nil.
    func message(forSpaceId spaceId: String) -> ScheduledMessage? {
        entries[spaceId]
    }

    /// Whether a scheduled (or overdue) message still occupies the space slot.
    func hasScheduled(in spaceId: String) -> Bool {
        entries[spaceId] != nil
    }

    /// Inserts (or replaces) the message scheduled for a space.
    func schedule(_ message: ScheduledMessage) {
        entries[message.spaceId] = message
        save()
    }

    func remove(spaceId: String) {
        guard entries.removeValue(forKey: spaceId) != nil else { return }
        save()
    }

    /// Marks every pending entry whose send time already passed as `overdue`
    /// (run once when the app starts: a send that should have happened while
    /// the app was closed is intentionally skipped, not retried).
    func markOverdueForPastDue() {
        var changed = false
        let now = Date()
        for (spaceId, message) in entries where message.status == .pending && message.scheduledAt <= now {
            var updated = message
            updated.status = .overdue
            entries[spaceId] = updated
            changed = true
        }
        if changed {
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ScheduledMessage].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
        objectWillChange.send()
    }
}