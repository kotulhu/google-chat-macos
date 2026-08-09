import Foundation
import SwiftUI

/// Маячки производительности для диагностики подвисаний ленты чата.
///
/// Все сообщения содержат метку потока (MAIN/BG), тег процесса, этап,
/// длительность и время от старта сессии. Управление: UserDefaults "perfBeaconsEnabled"
/// (по умолчанию включено).
///
/// Внутреннее состояние (intervals, lastRareLog) защищено рекурсивным локом,
/// т.к. маячки вызываются одновременно с MainActor и глобального executor'а
/// (сеть/декодирование) — без блокировки возникает гонка данных (EXC_BAD_ACCESS).
///
/// Теги:
///   Lenta  — жизненный цикл ленты (poll → cache → fetch → names → assign → cacheWrite)
///   Render — пересборка вью (bubbleBody, attributed, messagesChanged, scroll)
///   Image  — загрузка и декодирование картинок во вложениях
///   React  — загрузка/применение реакций
///   Bg     — фоновые проверки (60с чаты, 30с unread)
///   Net    — сетевые вызовы + JSON-декодирование в сервисе
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

    /// Точечная метка (всегда).
    static func mark(_ tag: String, phase: String, detail: String = "") {
        guard enabled else { return }
        log(String(format: "🕐 [%@][%@] %@ %@ t=%.0fms", thread(), tag, phase, detail, nowMs()))
    }

    /// Точечная метка с ограничением частоты (не чаще minInterval секунд на tag|phase).
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

    /// markRare для использования внутри ViewBuilder (возвращает EmptyView).
    static func markRareView(_ tag: String, phase: String, detail: String = "", minInterval: TimeInterval = 1.0) -> EmptyView {
        markRare(tag, phase: phase, detail: detail, minInterval: minInterval)
        return EmptyView()
    }

    /// Начало интервального замера.
    static func start(_ tag: String, phase: String) {
        guard enabled else { return }
        lock.lock()
        intervals["\(tag)|\(phase)"] = Date()
        lock.unlock()
    }

    /// Конец интервального замера. Логирует всегда (warnMs <= 0) или если >= warnMs.
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

    /// Замер синхронного участка (например, NSImage(data:) на главном потоке).
    static func measure(_ tag: String, phase: String, minMs: Double = 3, detail: String = "", _ work: () -> Void) {
        guard enabled else { work(); return }
        let start = Date()
        work()
        let ms = Date().timeIntervalSince(start) * 1000
        if ms >= minMs {
            log(String(format: "🕐 [%@][%@] %@ %.1fms %@", thread(), tag, phase, ms, detail))
        }
    }

    /// Замер синхронного участка с возвратом значения.
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
