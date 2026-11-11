import Foundation

/// Protocol trick to detect and unwrap `Optional<Wrapped>` values stored as `Any`.
/// `JSONSerialization` cannot serialize `Optional<Any>.none` or `ArraySlice`,
/// so we normalize them before passing the dictionary to the encoder.
private protocol AnyOptional {
    var isSome: Bool { get }
    var wrapped: Any { get }
}

extension Optional: AnyOptional {
    var isSome: Bool { self != nil }
    var wrapped: Any { self.map { $0 } ?? NSNull() }
}

/// Diagnostic observability logger for the "reactions displayed selectively" bug.
///
/// Writes one JSON object per line (JSON Lines) to
/// `~/Library/Logs/GogolChat/reactions.jsonl`. All writes happen on a private
/// serial queue so callers (including MainActor contexts) are never blocked.
/// The log rotates when it exceeds 5 MB (the current file is renamed to
/// `reactions.jsonl.1` and a new one is started).
///
/// Enabled via UserDefaults key `reactionDiagnosticsEnabled`. Default: ON in
/// Debug builds, OFF in Release builds. Check `isEnabled` before logging.
final class ReactionDiagnosticsLogger {
    static let shared = ReactionDiagnosticsLogger()

    private let queue = DispatchQueue(label: "GogolChat.ReactionDiagnostics", qos: .utility)
    private let fileManager = FileManager.default

    /// Log directory: ~/Library/Logs/GogolChat/
    private var logDirectory: URL {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/GogolChat", isDirectory: true)
    }

    /// Active log file.
    private var logURL: URL {
        logDirectory.appendingPathComponent("reactions.jsonl")
    }

    /// Rotation threshold: 5 MB.
    private let maxFileSize: UInt64 = 5 * 1024 * 1024

    /// Whether logging is enabled. Read once on init from UserDefaults.
    private(set) var isEnabled: Bool = false

    private init() {
        #if DEBUG
        let defaultEnabled = true
        #else
        let defaultEnabled = false
        #endif
        if UserDefaults.standard.object(forKey: "reactionDiagnosticsEnabled") == nil {
            // Key never set: use the build-config default.
            isEnabled = defaultEnabled
            UserDefaults.standard.set(defaultEnabled, forKey: "reactionDiagnosticsEnabled")
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: "reactionDiagnosticsEnabled")
        }
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    /// Toggle logging at runtime (also persists the choice).
    func setEnabled(_ enabled: Bool) {
        queue.async {
            self.isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "reactionDiagnosticsEnabled")
        }
    }

    /// Write one diagnostic record. Safe to call from any thread/actor.
    func log(
        stage: String,
        messageId: String?,
        spaceId: String?,
        createdTime: Date?,
        loadedVia: String?,
        fields: [String: Any]
    ) {
        guard isEnabled else { return }
        queue.async {
            self._log(stage: stage, messageId: messageId, spaceId: spaceId,
                      createdTime: createdTime, loadedVia: loadedVia, fields: fields)
        }
    }

    private func _log(
        stage: String,
        messageId: String?,
        spaceId: String?,
        createdTime: Date?,
        loadedVia: String?,
        fields: [String: Any]
    ) {
        do {
            try _logThrowing(
                stage: stage,
                messageId: messageId,
                spaceId: spaceId,
                createdTime: createdTime,
                loadedVia: loadedVia,
                fields: fields
            )
        } catch {
            // Best-effort logging; never throw.
        }
    }

    private func _logThrowing(
        stage: String,
        messageId: String?,
        spaceId: String?,
        createdTime: Date?,
        loadedVia: String?,
        fields: [String: Any]
    ) throws {
        var record: [String: Any] = [
            "ts": ISO8601DateFormatter.localString(from: Date()),
            "thread": Thread.isMainThread ? "MAIN" : String(describing: Thread.current),
            "stage": stage,
        ]
        if let messageId { record["messageId"] = String(messageId.suffix(6)) }
        if let spaceId { record["spaceId"] = String(spaceId.suffix(6)) }
        if let createdTime { record["createdTime"] = ISO8601DateFormatter.localString(from: createdTime) }
        if let loadedVia { record["loadedVia"] = loadedVia }
        for (k, v) in fields { record[k] = sanitize(v) }

        let data = try JSONSerialization.data(withJSONObject: record)
        guard let line = String(data: data, encoding: .utf8) else { return }
        _appendLine(line + "\n")
    }

    /// Recursively sanitizes a value so it is safe for `JSONSerialization`.
    /// - Replaces `nil` optionals with `NSNull()`
    /// - Converts `ArraySlice` to `Array`
    /// - Leaves everything else unchanged
    private func sanitize(_ value: Any) -> Any {
        if let optional = value as? AnyOptional {
            return optional.isSome ? sanitize(optional.wrapped) : NSNull()
        }
        if let array = value as? [Any] {
            return array.map { sanitize($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { sanitize($0) }
        }
        if value is String || value is Int || value is Double || value is Bool || value is NSNull {
            return value
        }
        // Fallback: stringify anything else (dates, URLs, Thread objects, etc.)
        return String(describing: value)
    }

    private func _appendLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: logURL.path) {
                let attrs = try fileManager.attributesOfItem(atPath: logURL.path)
                if let size = attrs[.size] as? UInt64, size >= maxFileSize {
                    let rotated = logDirectory.appendingPathComponent("reactions.jsonl.1")
                    try? fileManager.removeItem(at: rotated)
                    try fileManager.moveItem(at: logURL, to: rotated)
                }
            }
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Best-effort logging; never throw.
        }
    }

    // MARK: - Report

    /// Write a human-readable reactions report for the current chat to
    /// `reactions-report.txt` next to the log and return its path.
    func dumpReport(messages: [(id: String, time: Date?, loadedVia: String?,
                                   annotationTypes: [String: Int], summaryCount: Int,
                                   fetchedCount: Int, displayedCount: Int,
                                   status: String, reason: String)]) -> URL? {
        guard isEnabled else { return nil }
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        for m in messages {
            let shortId = m.id.suffix(6)
            let timeStr = m.time.map { formatter.string(from: $0) } ?? "-"
            lines.append(
                "\(shortId) | \(timeStr) | via=\(m.loadedVia ?? "-") | ann=\(m.annotationTypes) | " +
                "summary=\(m.summaryCount) | fetched=\(m.fetchedCount) | displayed=\(m.displayedCount) | " +
                "\(m.status) | \(m.reason)"
            )
        }
        let statusCounts = Dictionary(grouping: messages, by: { $0.status })
            .mapValues { $0.count }
            .sorted { $0.key < $1.key }
        lines.append("")
        lines.append("=== Сводка по статусам ===")
        for (status, count) in statusCounts {
            lines.append("\(status): \(count)")
        }
        let report = lines.joined(separator: "\n") + "\n"
        return queue.sync { _writeReport(report) }
    }

    private func _writeReport(_ report: String) -> URL? {
        guard let data = report.data(using: .utf8) else { return nil }
        let reportURL = logDirectory.appendingPathComponent("reactions-report.txt")
        do {
            try data.write(to: reportURL, options: .atomic)
            return reportURL
        } catch { return nil }
    }

    /// Dump a redacted copy of a raw message dictionary as JSON.
    /// Text fields (text, formattedText, authorName, displayName, etc.) are
    /// replaced with "<redacted len=N>". Everything else is preserved so the
    /// presence/absence of reaction-related API fields is visible.
    func dumpRawMessage(_ raw: [String: Any], for messageId: String) -> URL? {
        guard isEnabled else { return nil }
        let redacted = _redact(raw)
        guard let data = try? JSONSerialization.data(withJSONObject: redacted,
                                                      options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let shortId = String(messageId.suffix(6))
        let report = "=== Raw message JSON (redacted) for \(shortId) ===\n\(text)\n"
        return queue.sync { _writeReport(report) }
    }

    private func _redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (k, v) in dict {
                let lower = k.lowercased()
                if lower.contains("text") || lower.contains("name") || lower.contains("token")
                    || lower.contains("client") || lower.contains("email") || lower.contains("display") {
                    if let s = v as? String, !s.isEmpty {
                        result[k] = "<redacted len=\(s.count)>"
                    } else {
                        result[k] = v
                    }
                } else {
                    result[k] = _redact(v)
                }
            }
            return result
        } else if let arr = value as? [Any] {
            return arr.map { _redact($0) }
        } else {
            return value
        }
    }
}

extension ISO8601DateFormatter {
    static func localString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
