import AppKit
import CryptoKit

/// Memory + disk cache for user avatar images, keyed by the photo URL.
///
/// Entries are considered fresh for 24 hours, after which the image is
/// re-fetched from the network. Concurrent requests for the same URL are
/// coalesced so a long feed of messages from one author triggers a single
/// download.
actor AvatarCache {
    static let shared = AvatarCache()

    /// How long a downloaded avatar stays valid.
    private let ttl: TimeInterval = 24 * 60 * 60

    private let diskDirectory: URL
    private var memory: [String: (image: NSImage, date: Date)] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDirectory = caches.appendingPathComponent("GoogleChat/Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Returns the avatar for `url`, serving it from memory, a fresh (< 24 h)
    /// disk entry, or — on a miss — downloading and storing it.
    func image(for url: URL, accessToken: String?) async -> NSImage? {
        let key = Self.key(for: url)

        if let entry = memory[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.image
        }

        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(url: url, key: key, accessToken: accessToken)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    // MARK: - Loading

    private func load(url: URL, key: String, accessToken: String?) async -> NSImage? {
        if let disk = loadFreshFromDisk(key: key) {
            memory[key] = (disk, Date())
            return disk
        }

        guard let data = await download(url: url, accessToken: accessToken),
              let image = NSImage(data: data) else {
            return nil
        }

        try? data.write(to: diskURL(forKey: key), options: .atomic)
        memory[key] = (image, Date())
        return image
    }

    private func loadFreshFromDisk(key: String) -> NSImage? {
        let fileURL = diskURL(forKey: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl,
              let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    /// Downloads the avatar without auth first (public Google photo URLs), then
    /// retries with the bearer token for URLs that require authentication.
    private func download(url: URL, accessToken: String?) async -> Data? {
        if let data = await request(url: url, token: nil) {
            return data
        }
        if let accessToken, !accessToken.isEmpty {
            return await request(url: url, token: accessToken)
        }
        return nil
    }

    private func request(url: URL, token: String?) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    // MARK: - Paths

    private func diskURL(forKey key: String) -> URL {
        diskDirectory.appendingPathComponent("\(key).img")
    }

    private static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
