import Foundation
import Combine

/// Resolves and caches user display names and avatar URLs via the People API
/// batch endpoint.  Publishes updates through `objectWillChange` so SwiftUI
/// views can reactively re-render when a name finishes resolving.
@MainActor
final class NameResolver: ObservableObject {
    @Published private(set) var profiles: [String: ResolvedProfile] = [:]

    private let cacheDefaults = UserDefaults.standard
    private let namesKey = "nameResolver.names"
    private let photosKey = "nameResolver.photos"
    private let emailsKey = "nameResolver.emails"
    private let lastUpdateKey = "nameResolver.lastUpdate"
    private let maxCacheAge: TimeInterval = 7 * 24 * 3600 // 7 days

    private weak var chatService: GoogleChatService?
    private var inflight = Set<String>()

    // MARK: - Public API

    /// Binds the resolver to a live chat service (called once on configure).
    func configure(service: GoogleChatService) {
        self.chatService = service
        evictStaleCacheIfNeeded()
    }

    /// Synchronous lookup for a resolved display name.  Prefers a real name,
    /// falls back to the user's e-mail address, then to a short ID.
    func displayName(for userId: String) -> String {
        let profile = profiles[userId]
        if let name = profile?.displayName, !name.isEmpty { return name }
        if let email = profile?.email, !email.isEmpty { return email }
        return shortID(userId)
    }

    /// Synchronous lookup for a resolved avatar URL.
    func avatarURL(for userId: String) -> URL? {
        guard let str = profiles[userId]?.photoURL, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    /// Resolves every user ID not yet in cache.  The caller should pass the
    /// IDs in their `users/XXX` form (exactly as stored on messages/members).
    func resolve(userIds: Set<String>) async {
        guard let service = chatService, !userIds.isEmpty else { return }

        let missing = userIds.filter { profiles[$0] == nil && !inflight.contains($0) }
        guard !missing.isEmpty else { return }

        inflight.formUnion(missing)
        defer { inflight.subtract(missing) }

        var stillMissing = missing
        do {
            let result = try await service.fetchPeopleBatch(userIds: Array(missing))
            for (id, profile) in result {
                if profiles[id] != profile {
                    profiles[id] = profile
                }
            }
            stillMissing = missing.filter { profiles[$0] == nil }
        } catch {
            print("⚠️ NameResolver batch failed: \(error.localizedDescription)")
        }

        // The batch may have skipped some users (e.g. non-contacts) or failed
        // wholesale without `directory.readonly`.  Fall back to per-user
        // e-mail lookups which work with the `contacts.readonly` scope so
        // names degrade to e-mails instead of raw IDs.
        let served = await resolveEmailsIndividually(stillMissing)
        let didUpdate = served || missing.contains { profiles[$0] != nil }
        if didUpdate {
            saveCache()
            objectWillChange.send()
        }

        inflight.subtract(missing)
    }

    /// Tries per-user `people.get?personFields=emailAddresses` lookups for IDs
    /// that the batch could not resolve.  Returns true when anything changed.
    private func resolveEmailsIndividually(_ userIds: Set<String>) async -> Bool {
        guard let service = chatService, !userIds.isEmpty else { return false }
        var didUpdate = false
        for userId in userIds {
            guard profiles[userId] == nil else { continue }
            do {
                let email = try await service.fetchUserEmail(userId: userId)
                guard !email.isEmpty else { continue }
                let current = profiles[userId]
                let updated = ResolvedProfile(
                    displayName: current?.displayName,
                    photoURL: current?.photoURL,
                    email: current?.email ?? email
                )
                if current != updated {
                    profiles[userId] = updated
                    didUpdate = true
                }
            } catch {
                print("⚠️ NameResolver email fallback failed for \(userId): \(error.localizedDescription)")
            }
        }
        return didUpdate
    }

    /// Wipes the in-memory and on-disk cache (called on sign-out).
    func clearCache() {
        profiles.removeAll()
        inflight.removeAll()
        cacheDefaults.removeObject(forKey: namesKey)
        cacheDefaults.removeObject(forKey: photosKey)
        cacheDefaults.removeObject(forKey: emailsKey)
        cacheDefaults.removeObject(forKey: lastUpdateKey)
    }

    // MARK: - Persistence

    private func loadCache() {
        guard let names = cacheDefaults.dictionary(forKey: namesKey) as? [String: String] else { return }
        let photos = cacheDefaults.dictionary(forKey: photosKey) as? [String: String] ?? [:]
        let emails = cacheDefaults.dictionary(forKey: emailsKey) as? [String: String] ?? [:]
        var loaded: [String: ResolvedProfile] = [:]
        for (id, name) in names {
            loaded[id] = ResolvedProfile(displayName: name, photoURL: photos[id], email: emails[id])
        }
        for (id, email) in emails where loaded[id] == nil {
            loaded[id] = ResolvedProfile(displayName: nil, photoURL: nil, email: email)
        }
        profiles = loaded
    }

    private func saveCache() {
        var names: [String: String] = [:]
        var photos: [String: String] = [:]
        var emails: [String: String] = [:]
        for (id, profile) in profiles {
            if let name = profile.displayName { names[id] = name }
            if let url = profile.photoURL { photos[id] = url }
            if let email = profile.email { emails[id] = email }
        }
        cacheDefaults.set(names, forKey: namesKey)
        cacheDefaults.set(photos, forKey: photosKey)
        cacheDefaults.set(emails, forKey: emailsKey)
        cacheDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
    }

    private func evictStaleCacheIfNeeded() {
        loadCache()
        guard !profiles.isEmpty else { return }
        if let last = cacheDefaults.object(forKey: lastUpdateKey) as? TimeInterval,
           Date().timeIntervalSince1970 - last > maxCacheAge {
            print("🗑 NameResolver: cache older than 7 days, clearing")
            clearCache()
        }
    }

    // MARK: - Helpers

    private func shortID(_ userId: String) -> String {
        "User " + userId.replacingOccurrences(of: "users/", with: "").suffix(6)
    }
}
