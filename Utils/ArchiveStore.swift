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
/// Everything funnels through a private serial queue. In-memory state is
/// updated immediately and flushed to disk after a short debounce, so rapid
/// reaction/scroll churn does not hammer the filesystem.
final class ArchiveStore {
    static let shared = ArchiveStore()

    private let rootDir: URL
    private let spacesDir: URL
    private let mediaDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let queue = DispatchQueue(label: "gogolchatsuite.archive", qos: .utility)
    private var spaces: [String: SpaceArchive] = [:]
    private var summaryByID: [String: SpaceArchiveSummary] = [:]
    private var mediaEntries: [String: MediaEntry] = [:]
    private var pendingFlush: DispatchWorkItem?

    private init() {
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
    var archiveRootURL: URL { rootDir }

    // MARK: - Message merging

    /// Merges a page of messages into the archive of a space (union by id,
    /// newest wins). Safe to call repeatedly with overlapping pages.
    func merge(spaceId: String, spaceName: String, messages incoming: [Message]) {
        guard !spaceId.isEmpty else { return }
        queue.async { [self] in
            var archive = spaces[spaceId] ?? SpaceArchive(spaceId: spaceId, spaceName: spaceName, updatedAt: Date(), messages: [])
            archive.spaceName = spaceName
            var byID: [String: Message] = [:]
            for message in archive.messages {
                byID[message.id] = message
            }
            for message in incoming {
                byID[message.id] = message
            }
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
            scheduleFlush()
        }
    }

    /// Merges a single (possibly updated) message — e.g. after a reaction toggle.
    func mergeMessage(spaceId: String, message: Message) {
        merge(spaceId: spaceId, spaceName: spaces[spaceId]?.spaceName ?? message.authorName, messages: [message])
    }

    /// Applies any still-pending writes right away (used before exporting).
    func flushNow() {
        queue.sync { flushLocked() }
    }

    // MARK: - Media

    /// Stores attachment bytes under a deterministic name derived from the
    /// attachment id (ignored when a same-size copy already exists). Returns
    /// the stored file name, or nil when there is nothing to store.
    @discardableResult
    func storeMedia(data: Data, attachmentId: String, mimeType: String, originalName: String) -> String? {
        guard !attachmentId.isEmpty, !data.isEmpty else { return nil }
        let storedName = Self.mediaStoredName(for: attachmentId, mimeType: mimeType, originalName: originalName)
        queue.async { [self] in
            if let existing = mediaEntries[attachmentId],
               existing.size == Int64(data.count),
               FileManager.default.fileExists(atPath: mediaDir.appendingPathComponent(existing.storedName).path) {
                return
            }
            try? data.write(to: mediaDir.appendingPathComponent(storedName), options: [.atomic])
            mediaEntries[attachmentId] = MediaEntry(
                attachmentId: attachmentId,
                originalName: originalName,
                contentType: mimeType,
                size: Int64(data.count),
                storedName: storedName
            )
            scheduleFlush()
        }
        return storedName
    }

    /// The deterministic media file name for an attachment id (no disk IO).
    func mediaStoredName(attachmentId: String) -> String? {
        queue.sync {
            mediaEntries[attachmentId]?.storedName
        }
    }

    /// Raw bytes of a stored media file, or nil when missing.
    func mediaData(storedName: String) -> Data? {
        let url = mediaDir.appendingPathComponent(storedName)
        return queue.sync {
            try? Data(contentsOf: url)
        }
    }

    /// Deterministic file name inside `media/` for an attachment id.
    static func mediaStoredName(for attachmentId: String, mimeType: String, originalName: String) -> String {
        let hash = SHA256.hash(data: Data(attachmentId.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(hash).\(fileExtension(forMIME: mimeType, originalName: originalName))"
    }

    private static func fileExtension(forMIME mimeType: String, originalName: String) -> String {
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
        queue.sync {
            loadSpaceLocked(spaceId)?.messages
        }
    }

    /// Metadata of every archived space (sorted by most recent activity).
    func summaries() -> [SpaceArchiveSummary] {
        queue.sync {
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
    }

    // MARK: - Load / lock helpers

    private func loadIndexAndManifest() {
        queue.async { [self] in
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
    }

    private func loadSpaceLocked(_ spaceId: String) -> SpaceArchive? {
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
        pendingFlush?.cancel()
        let workItem = DispatchWorkItem { [self] in
            flushLocked()
        }
        pendingFlush = workItem
        queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func flushLocked() {
        for archive in spaces.values {
            guard let data = try? encoder.encode(archive) else { continue }
            let url = spacesDir.appendingPathComponent(Self.fileName(for: archive.spaceId))
            try? data.write(to: url, options: [.atomic])
        }
        if !summaryByID.isEmpty, let data = try? encoder.encode(Array(summaryByID.values)) {
            try? data.write(to: rootDir.appendingPathComponent("index.json"), options: [.atomic])
        }
        if !mediaEntries.isEmpty, let data = try? encoder.encode(mediaEntries) {
            try? data.write(to: rootDir.appendingPathComponent("manifest.json"), options: [.atomic])
        }
    }

    private static func fileName(for spaceId: String) -> String {
        "\(sha(spaceId)).json"
    }

    private static func sha(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}