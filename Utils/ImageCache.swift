import Foundation
import CryptoKit
import SwiftUI

/// A memory + disk cache for attachment data (used for images and files),
    /// keyed by resource/attachment name.
    class AttachmentCache {
    static let shared = AttachmentCache()
    private static let memoryLimitBytes = 50 * 1024 * 1024
    private let cache = NSCache<NSString, NSData>()
    private let diskDirectory: URL
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = Self.memoryLimitBytes
        diskDirectory = CachePaths.baseDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }
    
    /// Returns cached data (memory first, then disk), or nil on a full miss.
    func get(forKey key: String) -> Data? {
        if let data = cache.object(forKey: key as NSString) as? Data {
            print("📎 Attachment cache memory hit: \(key)")
            return data
        }
        
        let fileURL = diskURL(forKey: key)
        guard let data = try? Data(contentsOf: fileURL) else {
            print("📎 Attachment cache miss: \(key)")
            return nil
        }
        
        print("📎 Attachment cache disk hit: \(key)")
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return data
    }
    
    /// Stores data in memory and on disk.
    func set(_ data: Data, forKey key: String) {
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        try? data.write(to: diskURL(forKey: key), options: [.atomic])
        print("📎 Attachment cache stored: \(key), size: \(data.count)")
    }
    
    /// Resolves the on-disk file for a key.
    private func diskURL(forKey key: String) -> URL {
        diskDirectory.appendingPathComponent(CachePaths.fileName(forKey: key))
    }
}

typealias ImageCache = AttachmentCache

/// Disk-only JSON cache for the message lists of each space.
class MessageCache {
    static let shared = MessageCache()
    private let diskDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        diskDirectory = CachePaths.baseDirectory.appendingPathComponent("Messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /// Loads the cached messages of a space, or nil if nothing is stored.
    func get(spaceId: String) -> [Message]? {
        let fileURL = diskURL(forKey: spaceId)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode([Message].self, from: data)
    }
    
    /// Encodes and stores the messages of a space.
    func set(_ messages: [Message], forSpaceId spaceId: String) {
        guard let data = try? encoder.encode(messages) else {
            return
        }
        try? data.write(to: diskURL(forKey: spaceId), options: [.atomic])
    }
    
    /// Deletes every cached message file.
    func removeAll() {
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }
    
    /// Resolves the on-disk JSON file for a space.
    private func diskURL(forKey key: String) -> URL {
        diskDirectory.appendingPathComponent(CachePaths.fileName(forKey: key, extension: "json"))
    }
}

/// Shared location + hashed file-name helpers for the attachment and message
/// caches.
private enum CachePaths {
    static let baseDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("GoogleChat", isDirectory: true)
    }()
    
    static func fileName(forKey key: String, extension fileExtension: String = "bin") -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(fileExtension)"
    }
}
