import Foundation
import SQLite3

/// One locally-stored message row. `rawJson` keeps the complete message JSON
/// (exactly as returned by the Chat API), so any future field that is not yet
/// extracted into a dedicated column remains available for search/UI tasks.
struct MessageHistoryRecord {
    let id: String
    let spaceId: String
    let senderId: String?
    let text: String
    let createdTime: String?
    let isDeleted: Bool
    let rawJson: String
}

/// Persistent, unbounded message history backed by SQLite.
///
/// Every message that the app receives from the Chat API (initial feed load,
/// polling ticks and older-history pagination) is upserted here in parallel to
/// the in-memory feed. A message that arrives again — edited, or carrying a
/// `deletionMetadata` — overwrites the previous row, which makes edits and
/// deletions converge naturally without any background re-validation.
///
/// This store is deliberately separate from the lightweight feed cache
/// (`MessageCache`): the table below grows without limit and is never cleared
/// on normal app shutdown by design. There is no query/search API yet — that is
/// intentionally out of scope for this task.
final class MessageHistoryStore {
    static let shared = MessageHistoryStore()

    /// SQLite's `SQLITE_TRANSIENT` macro is not visible to Swift; the raw value
    /// `-1` tells it to copy the bound buffer instead of taking ownership.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "khtulhu.GoogleChat.messageHistory", qos: .utility)

    private var databaseURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Gogol Chat", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("messages.sqlite")
    }

    private init() {
        openDatabase()
        print("📚 [History] store ready at \(databaseURL.path)")
    }

    // MARK: - Public API

    /// Inserts new rows and overwrites existing ones (keyed by message `id`)
    /// with the latest payload. Asynchronous and non-blocking; the write is
    /// serialized on a background queue so it can be called from any flow.
    func upsertMessages(_ records: [MessageHistoryRecord]) {
        guard !records.isEmpty else { return }
        queue.async { [weak self] in
            self?.upsertMessagesOnQueue(records)
        }
    }

    // MARK: - Database plumbing

    private func openDatabase() {
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            print("❌ [History] Cannot create DB directory: \(error)")
            return
        }

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            if let db {
                print("❌ [History] Cannot open DB: \(String(cString: sqlite3_errmsg(db)))")
                sqlite3_close(db)
                self.db = nil
            }
            return
        }

        exec(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                spaceId TEXT NOT NULL,
                senderId TEXT,
                text TEXT NOT NULL DEFAULT '',
                createdTime TEXT,
                isDeleted INTEGER NOT NULL DEFAULT 0,
                rawJson TEXT NOT NULL
            );
            """
        )
        exec("CREATE INDEX IF NOT EXISTS idx_messages_space ON messages(spaceId);")
        exec("CREATE INDEX IF NOT EXISTS idx_messages_space_created ON messages(spaceId, createdTime);")
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            if let errorMessage {
                print("❌ [History] exec failed: \(String(cString: errorMessage))")
                sqlite3_free(errorMessage)
            }
            return false
        }
        return true
    }

    private func upsertMessagesOnQueue(_ records: [MessageHistoryRecord]) {
        guard let db else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT;", nil, nil, nil) }

        let sql = """
        INSERT INTO messages (id, spaceId, senderId, text, createdTime, isDeleted, rawJson)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            spaceId = excluded.spaceId,
            senderId = excluded.senderId,
            text = excluded.text,
            createdTime = excluded.createdTime,
            isDeleted = excluded.isDeleted,
            rawJson = excluded.rawJson;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ [History] prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            bindText(record.id, at: 1, statement: statement)
            bindText(record.spaceId, at: 2, statement: statement)
            bindTextOrNull(record.senderId, at: 3, statement: statement)
            bindText(record.text, at: 4, statement: statement)
            bindTextOrNull(record.createdTime, at: 5, statement: statement)
            sqlite3_bind_int(statement, 6, record.isDeleted ? 1 : 0)
            bindText(record.rawJson, at: 7, statement: statement)

            let stepResult = sqlite3_step(statement)
            if stepResult != SQLITE_DONE {
                print("❌ [History] step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, Self.sqliteTransient)
    }

    private func bindTextOrNull(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            bindText(value, at: index, statement: statement)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}