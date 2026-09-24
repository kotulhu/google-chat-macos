import Foundation
import CryptoKit

/// A persisted snapshot of a single chat's message history.
struct SpaceArchive: Codable {
    var spaceId: String
    var spaceName: String
    var updatedAt: Date
    var messages: [Message]
}

/// Lightweight per-space metadata used to list archived chats without
/// decoding every message list.
struct SpaceArchiveSummary: Codable, Identifiable {
    var spaceId: String
    var spaceName: String
    var messageCount: Int
    var updatedAt: Date
    var id: String { spaceId }
}

/// Metadata of one archived media file (keyed by attachment id in the manifest).
struct MediaEntry: Codable {
    var attachmentId: String
    var originalName: String
    var contentType: String
    var size: Int64
    var storedName: String
}

/// Local, write-once message + media archive used as the source for HTML exports.
///
/// Layout under `~/Library/Application Support/Gogol Chat/Archive/`:
///   - `spaces/<sha256(spaceId)>.json` — merged message history of one space
///   - `media/<sha256(attachmentId)>.<ext>` — deduplicated attachment bytes
///   - `manifest.json`                 — attachment id → media entry map
///   - `index.json`                    — per-space summaries for the export list
///
/// The store is a Swift actor: all in-memory state is mutated on its own
/// executor, which rules out the cross-thread array aliasing that could crash
/// the app. Writes are debounced through a single `Task` and only spaces whose
/// contents actually changed are rewritten to disk.
actor ArchiveStore {
    static let shared = ArchiveStore()

    nonisolated private let rootDir: URL
    nonisolated private let spacesDir: URL
    nonisolated private let mediaDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var spaces: [String: SpaceArchive] = [:]
    private var summaryByID: [String: SpaceArchiveSummary] = [:]
    private var mediaEntries: [String: MediaEntry] = [:]
    private var dirtySpaceIDs: Set<String> = []
    private var flushTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        rootDir = appSupport.appendingPathComponent("Gogol Chat/Archive", isDirectory: true)
        spacesDir = rootDir.appendingPathComponent("spaces", isDirectory: true)
        mediaDir = rootDir.appendingPathComponent("media", isDirectory: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        loadIndexAndManifest()
    }

    /// The archive root directory (exposed for debugging/tests).
    nonisolated var archiveRootURL: URL { rootDir }

    // MARK: - Message merging

    /// Merges a page of messages into the archive of a space (union by id,
    /// newest wins). Only marks the space dirty when the incoming page actually
    /// changed anything, so routine 60-second polls stay cheap.
    func merge(spaceId: String, spaceName: String, messages incoming: [Message]) {
        guard !spaceId.isEmpty, !incoming.isEmpty else { return }
        var archive = spaces[spaceId] ?? loadSpace(spaceId)
            ?? SpaceArchive(spaceId: spaceId, spaceName: spaceName, updatedAt: Date(), messages: [])
        archive.spaceName = spaceName
        var byID: [String: Message] = [:]
        for message in archive.messages {
            byID[message.id] = message
        }
        var changed = false
        for message in incoming {
            if let existing = byID[message.id] {
                if existing != message {
                    changed = true
                }
            } else {
                changed = true
            }
            byID[message.id] = message
        }
        guard changed else { return }
        let merged = Array(byID.values)
        archive.messages = merged.sorted { ($0.timestamp, $0.id) > ($1.timestamp, $1.id) }
        archive.updatedAt = Date()
        spaces[spaceId] = archive
        summaryByID[spaceId] = SpaceArchiveSummary(
            spaceId: spaceId,
            spaceName: spaceName,
            messageCount: merged.count,
            updatedAt: archive.updatedAt
        )
        dirtySpaceIDs.insert(spaceId)
        scheduleFlush()
    }

    /// Merges a single (possibly updated) message — e.g. after a reaction toggle.
    func mergeMessage(spaceId: String, message: Message) {
        guard !spaceId.isEmpty else { return }
        if spaces[spaceId] == nil {
            spaces[spaceId] = loadSpace(spaceId)
        }
        merge(spaceId: spaceId, spaceName: spaces[spaceId]?.spaceName ?? message.authorName, messages: [message])
    }

    /// Applies any still-pending writes right away (used before exporting).
    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        persistLocked(dirtyOnly: false)
    }

    // MARK: - Media

    /// Stores attachment bytes under a deterministic name derived from the
    /// attachment id (ignored when a same-size copy already exists). Returns
    /// the stored file name, or nil when there is nothing to store.
    @discardableResult
    func storeMedia(data: Data, attachmentId: String, mimeType: String, originalName: String) -> String? {
        guard !attachmentId.isEmpty, !data.isEmpty else { return nil }
        if let existing = mediaEntries[attachmentId],
           existing.size == Int64(data.count),
           FileManager.default.fileExists(atPath: mediaDir.appendingPathComponent(existing.storedName).path) {
            return existing.storedName
        }
        let storedName = Self.mediaStoredName(for: attachmentId, mimeType: mimeType, originalName: originalName)
        let url = mediaDir.appendingPathComponent(storedName)
        guard (try? data.write(to: url, options: [.atomic])) != nil else { return nil }
        mediaEntries[attachmentId] = MediaEntry(
            attachmentId: attachmentId,
            originalName: originalName,
            contentType: mimeType,
            size: Int64(data.count),
            storedName: storedName
        )
        scheduleFlush()
        return storedName
    }

    /// The stored media file name for an attachment id, when already archived.
    func mediaStoredName(attachmentId: String) -> String? {
        mediaEntries[attachmentId]?.storedName
    }

    /// Raw bytes of a stored media file, or nil when missing (pure disk read).
    nonisolated func mediaData(storedName: String) -> Data? {
        let url = mediaDir.appendingPathComponent(storedName)
        return try? Data(contentsOf: url)
    }

    /// Deterministic file name inside `media/` for an attachment id.
    nonisolated static func mediaStoredName(for attachmentId: String, mimeType: String, originalName: String) -> String {
        let hash = SHA256.hash(data: Data(attachmentId.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(hash).\(fileExtension(forMIME: mimeType, originalName: originalName))"
    }

    private nonisolated static func fileExtension(forMIME mimeType: String, originalName: String) -> String {
        let mapped: [String: String] = [
            "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif",
            "image/webp": "webp", "image/heic": "heic", "video/mp4": "mp4",
            "video/quicktime": "mov", "video/webm": "webm",
            "application/pdf": "pdf", "audio/mpeg": "mp3", "audio/mp4": "m4a"
        ]
        if let ext = mapped[mimeType.lowercased()] {
            return ext
        }
        let fromName = URL(fileURLWithPath: originalName).pathExtension.lowercased()
        return fromName.isEmpty ? "bin" : fromName
    }

    // MARK: - Reads

    /// Messages of an archived space (newest first), or nil when not present.
    func messages(forSpaceId spaceId: String) -> [Message]? {
        loadSpace(spaceId)?.messages
    }

    /// Metadata of every archived space (sorted by most recent activity).
    func summaries() -> [SpaceArchiveSummary] {
        // Fall back to scanning files when the index is missing.
        if summaryByID.isEmpty {
            let files = (try? FileManager.default.contentsOfDirectory(at: spacesDir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let archive = try? decoder.decode(SpaceArchive.self, from: data) {
                    summaryByID[archive.spaceId] = SpaceArchiveSummary(
                        spaceId: archive.spaceId,
                        spaceName: archive.spaceName,
                        messageCount: archive.messages.count,
                        updatedAt: archive.updatedAt
                    )
                }
            }
        }
        return summaryByID.values.sorted { ($0.updatedAt, $0.spaceName) > ($1.updatedAt, $1.spaceName) }
    }

    // MARK: - Load / persistence helpers

    private func loadIndexAndManifest() {
        let manifestURL = rootDir.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let entries = try? decoder.decode([String: MediaEntry].self, from: data) {
            mediaEntries = entries
        }
        let indexURL = rootDir.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let list = try? decoder.decode([SpaceArchiveSummary].self, from: data) {
            for summary in list {
                summaryByID[summary.spaceId] = summary
            }
        }
    }

    private func loadSpace(_ spaceId: String) -> SpaceArchive? {
        if let cached = spaces[spaceId] {
            return cached
        }
        let file = spacesDir.appendingPathComponent(Self.fileName(for: spaceId))
        guard let data = try? Data(contentsOf: file),
              let archive = try? decoder.decode(SpaceArchive.self, from: data) else {
            return nil
        }
        spaces[spaceId] = archive
        return archive
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            await self?.persistAfterDebounce()
        }
    }

    /// Runs on the actor after the debounce window; clears the in-flight task,
    /// writes dirty spaces and re-arms when new writes arrived meanwhile.
    private func persistAfterDebounce() {
        flushTask = nil
        persistLocked(dirtyOnly: true)
        if !dirtySpaceIDs.isEmpty {
            scheduleFlush()
        }
    }

    /// Writes dirty (or, when `dirtyOnly` is false, every) archived space to
    /// disk along with the index and media manifest.
    private func persistLocked(dirtyOnly: Bool) {
        var wroteSpaces = false
        for (spaceID, archive) in spaces {
            guard !dirtyOnly || dirtySpaceIDs.contains(spaceID) else { continue }
            guard let data = try? encoder.encode(archive) else { continue }
            let url = spacesDir.appendingPathComponent(Self.fileName(for: spaceID))
            try? data.write(to: url, options: [.atomic])
            wroteSpaces = true
        }
        dirtySpaceIDs.removeAll()
        if wroteSpaces, let data = try? encoder.encode(Array(summaryByID.values)) {
            try? data.write(to: rootDir.appendingPathComponent("index.json"), options: [.atomic])
        }
        if !mediaEntries.isEmpty, let data = try? encoder.encode(mediaEntries) {
            try? data.write(to: rootDir.appendingPathComponent("manifest.json"), options: [.atomic])
        }
    }

    nonisolated private static func fileName(for spaceId: String) -> String {
        "\(sha(spaceId)).json"
    }

    nonisolated private static func sha(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}