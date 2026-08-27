import Foundation
import SwiftUI

/// Performance beacons for diagnosing chat-feed hangs.
///
/// Every message carries a thread label (MAIN/BG), a process tag, a phase, a
/// duration and the time-since-session-start. Controlled via UserDefaults
/// "perfBeaconsEnabled" (on by default).
///
/// Internal state (intervals, lastRareLog) is guarded by a recursive lock,
/// because beacons are invoked from both the MainActor and the global executor
/// (network/decoding) — without locking this is a data race (EXC_BAD_ACCESS).
///
/// Tags:
///   Lenta  — feed lifecycle (poll → cache → fetch → names → assign → cacheWrite)
///   Render — view rebuilds (bubbleBody, attributed, messagesChanged, scroll)
///   Image  — image loading and decoding for attachments
///   React  — reaction loading/application
///   Bg     — background checks (60s spaces, 30s unread)
///   Net    — network calls + JSON decoding in the service
enum PerfBeacon {
    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "perfBeaconsEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "perfBeaconsEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "perfBeaconsEnabled") }
    }

    private static let lock = NSRecursiveLock()
    private static let startDate = Date()
    private static var intervals: [String: Date] = [:]
    private static var lastRareLog: [String: Date] = [:]

    private static func thread() -> String {
        Thread.isMainThread ? "MAIN" : "BG"
    }

    private static func nowMs() -> Double {
        Date().timeIntervalSince(startDate) * 1000
    }

    private static func log(_ message: String) {
        print(message)
    }

    /// Point-in-time mark, always logged.
    static func mark(_ tag: String, phase: String, detail: String = "") {
        guard enabled else { return }
        log(String(format: "🕐 [%@][%@] %@ %@ t=%.0fms", thread(), tag, phase, detail, nowMs()))
    }

    /// Point mark with rate limiting (at most once per `minInterval` seconds
    /// per tag|phase).
    static func markRare(_ tag: String, phase: String, detail: String = "", minInterval: TimeInterval = 1.0) {
        guard enabled else { return }
        let key = "\(tag)|\(phase)"
        let now = Date()
        lock.lock()
        let shouldLog: Bool
        if let last = lastRareLog[key], now.timeIntervalSince(last) < minInterval {
            shouldLog = false
        } else {
            lastRareLog[key] = now
            shouldLog = true
        }
        lock.unlock()
        if shouldLog {
            mark(tag, phase: phase, detail: detail)
        }
    }

    /// `markRare` for use inside a ViewBuilder (returns an `EmptyView`).
    static func markRareView(_ tag: String, phase: String, detail: String = "", minInterval: TimeInterval = 1.0) -> EmptyView {
        markRare(tag, phase: phase, detail: detail, minInterval: minInterval)
        return EmptyView()
    }

    /// Starts an interval measurement.
    static func start(_ tag: String, phase: String) {
        guard enabled else { return }
        lock.lock()
        intervals["\(tag)|\(phase)"] = Date()
        lock.unlock()
    }

    /// Ends an interval measurement. Logs always (when warnMs <= 0) or when
    /// the elapsed time is >= warnMs.
    static func end(_ tag: String, phase: String, detail: String = "", warnMs: Double = 0) {
        guard enabled else { return }
        lock.lock()
        let start = intervals.removeValue(forKey: "\(tag)|\(phase)")
        lock.unlock()
        guard let start else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        guard warnMs <= 0 || ms >= warnMs else { return }
        let flag = warnMs > 0 && ms >= warnMs ? "⚠️ " : ""
        log(String(format: "%@🕐 [%@][%@] %@ %.1fms %@", flag, thread(), tag, phase, ms, detail))
    }

    /// Measures a synchronous block (e.g. `NSImage(data:)` on the main thread).
    static func measure(_ tag: String, phase: String, minMs: Double = 3, detail: String = "", _ work: () -> Void) {
        guard enabled else { work(); return }
        let start = Date()
        work()
        let ms = Date().timeIntervalSince(start) * 1000
        if ms >= minMs {
            log(String(format: "🕐 [%@][%@] %@ %.1fms %@", thread(), tag, phase, ms, detail))
        }
    }

    /// Measures a synchronous block that returns a value.
    @discardableResult
    static func measureReturn<T>(_ tag: String, phase: String, minMs: Double = 3, detail: String = "", _ work: () throws -> T) rethrows -> T {
        guard enabled else { return try work() }
        let start = Date()
        let result = try work()
        let ms = Date().timeIntervalSince(start) * 1000
        if ms >= minMs {
            log(String(format: "🕐 [%@][%@] %@ %.1fms %@", thread(), tag, phase, ms, detail))
        }
        return result
    }
}
