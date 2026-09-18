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
    /// Profiles that have neither a name nor an e-mail yet and whose one-shot
    /// e-mail lookup is already scheduled in this session (so we don't hammer
    /// the People API on every poll for users nobody can resolve).
    private var pendingEmailLookups = Set<String>()

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
        // A cached/known profile with neither a name nor an e-mail (e.g. an
        // external user the directory reduced to an empty profile) still gets
        // exactly one per-session e-mail attempt, so names degrade to e-mails
        // instead of raw IDs instead of silently staying as such forever.
        if profile != nil, chatService != nil, !pendingEmailLookups.contains(userId) {
            pendingEmailLookups.insert(userId)
            Task { [weak self] in
                guard let self else { return }
                let updated = await self.resolveEmailOnly(for: userId)
                self.pendingEmailLookups.remove(userId)
                if updated {
                    self.saveCache()
                    self.objectWillChange.send()
                }
            }
        }
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
        var emptyProfiles: [String] = []
        do {
            let result = try await service.fetchPeopleBatch(userIds: Array(missing))
            for (id, profile) in result {
                if profiles[id] != profile {
                    profiles[id] = profile
                }
                // The directory batch may return a profile for everybody without
                // a usable name *or* an e-mail.  Keep those candidates for the
                // per-user e-mail fallback below.
                if (profile.displayName?.isEmpty ?? true) && (profile.email?.isEmpty ?? true) {
                    emptyProfiles.append(id)
                }
            }
            stillMissing = missing.filter { profiles[$0] == nil }
        } catch {
            print("⚠️ NameResolver batch failed: \(error.localizedDescription)")
            emptyProfiles = Array(missing)
        }

        // The batch may have skipped some users (e.g. non-contacts) or failed
        // wholesale without `directory.readonly`.  Fall back to per-user
        // e-mail lookups which work with the `contacts.readonly` scope so
        // names degrade to e-mails instead of raw IDs.
        let candidates = Set(stillMissing).union(emptyProfiles)
        let served = await resolveEmailsIndividually(candidates)
        let didUpdate = served || missing.contains { profiles[$0] != nil }
        if didUpdate {
            saveCache()
            objectWillChange.send()
        }
    }

    /// Tries per-user `people.get?personFields=emailAddresses` lookups for IDs
    /// whose profiles still lack an e-mail.  Returns true when anything changed.
    private func resolveEmailsIndividually(_ userIds: Set<String>) async -> Bool {
        guard chatService != nil, !userIds.isEmpty else { return false }
        var didUpdate = false
        for userId in userIds {
            if await resolveEmailOnly(for: userId) {
                didUpdate = true
            }
        }
        return didUpdate
    }

    /// Fetches a missing e-mail for one user and merges it into the existing
    /// profile (preserving any name/photo already resolved).  Skips users that
    /// already have an e-mail.  Returns true when the profile changed.
    private func resolveEmailOnly(for userId: String) async -> Bool {
        guard profiles[userId]?.email == nil else { return false }
        guard let service = chatService else { return false }
        do {
            let email = try await service.fetchUserEmail(userId: userId)
            guard !email.isEmpty else { return false }
            let current = profiles[userId]
            let updated = ResolvedProfile(
                displayName: current?.displayName,
                photoURL: current?.photoURL,
                email: current?.email ?? email
            )
            if current != updated {
                profiles[userId] = updated
                return true
            }
        } catch {
            print("⚠️ NameResolver email fallback failed for \(userId): \(error.localizedDescription)")
        }
        return false
    }

    /// Wipes the in-memory and on-disk cache (called on sign-out).
    func clearCache() {
        profiles.removeAll()
        inflight.removeAll()
        pendingEmailLookups.removeAll()
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
