import Foundation

/// Актор загрузки и кэширования GIF.
///
/// - Дедупликация по ключу (messageId + url).
/// - Состояния: notLoaded / loading / loaded / failed.
/// - Загрузка не привязана к жизненному циклу строки (detached Task) — не
///   отменяется при уходе из viewport. Отменяется только при смене пространства.
/// - Лимит параллелизма 3, таймаут, повтор для 429/5xx/сетевых ошибок
///   (паузы 2 и 4 с, максимум 2 попытки), отмену повтором не лечить.
/// - uri запрашивается без Authorization; на 401/403 повторяем с токеном.
/// - Кэш: NSCache в памяти + дисковый в Caches/GogolChat/gifs (~100 МБ,
///   удаление старых). Файлы > 15 МБ не загружаются.
actor GifLoader {
    static let shared = GifLoader()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let fileManager = FileManager.default
    private let diskCacheDir: URL
    private let maxDiskSize: UInt64 = 100 * 1024 * 1024 // ~100 МБ
    private let maxFileSize: UInt64 = 15 * 1024 * 1024   // 15 МБ
    private let requestTimeout: TimeInterval = 30

    /// Задачи загрузки в полёте (дедупликация).
    private var inflight: [String: Task<Data?, Never>] = [:]
    /// Состояния по ключу.
    private var states: [String: LoadState] = [:]

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = caches.appendingPathComponent("GogolChat/gifs", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 МБ в памяти
    }

    /// Ключ для дедупликации.
    private func key(messageId: String, url: URL) -> String {
        "\(messageId)|\(url.absoluteString)"
    }

    /// Дисковый путь для ключа.
    private func diskPath(for key: String) -> URL {
        let hash = key.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "=", with: "_")
        return diskCacheDir.appendingPathComponent(hash)
    }

    /// Состояние загрузки.
    private enum LoadState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(retryAfter: Date, attempts: Int)
    }

    /// Загрузить GIF-данные.
    /// - Returns: Данные GIF или nil, если файл > 15 МБ (показать как ссылку).
    func load(messageId: String, url: URL, accessToken: String? = nil) async -> Data? {
        let key = key(messageId: messageId, url: url)

        // 1. Память
        if let data = memoryCache.object(forKey: url as NSURL) as Data? {
            return data
        }

        // 2. Диск
        if let data = try? Data(contentsOf: diskPath(for: key)) {
            memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            return data
        }

        // 3. Уже в полёте — ждём ту же задачу
        if let existing = inflight[key] {
            return await existing.value
        }

        // 4. Состояние failed с истекшим backoff — можно повторить
        if let state = states[key] {
            switch state {
            case .failed(let retryAfter, let attempts):
                if attempts >= 2 { return nil }
                if Date() < retryAfter { return nil }
                // иначе fall through к новой загрузке
            default:
                return nil
            }
        }

        // 5. Лимит параллелизма (3). Превышен — возвращаем nil, view покажет
        //    состояние загрузки и повторит по своей инициативе позже.
        if inflight.count >= 3 { return nil }

        states[key] = .loading

        // Detached: задача НЕ наследует отмену от `.task` строки/viewport —
        // уход из viewport не должен превращать загрузку в NSURLErrorCancelled.
        let task = Task.detached { [weak self] () -> Data? in
            guard let self else { return nil }
            do {
                return try await self.fetchWithRetry(url: url, key: key, accessToken: accessToken)
            } catch {
                await self.setFailed(key: key, attempts: 2)
                await self.log(url: url, status: nil, size: nil, duration: 0,
                               state: "failed", usedAuth: false, messageId: messageId)
                return nil
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight.removeValue(forKey: key)

        if let data = result {
            await setLoaded(key: key, data: data, url: url)
        } else {
            await setFailed(key: key, attempts: 2)
        }
        return result
    }

    private func setLoaded(key: String, data: Data, url: URL) {
        states[key] = .loaded
        try? data.write(to: diskPath(for: key))
        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        enforceDiskLimit()
    }

    private func setFailed(key: String, attempts: Int) {
        states[key] = .failed(retryAfter: .distantPast, attempts: attempts)
    }

    /// Загрузка с повторами (2 и 4 с, максимум 2 попытки) и auth-fallback.
    private func fetchWithRetry(url: URL, key: String, accessToken: String?) async throws -> Data? {
        let started = Date()
        var attempts = 0
        var usedAuth = false

        while true {
            attempts += 1
            // Первый запрос — без Authorization; на 401/403 повторяем с токеном.
            let request = urlRequest(url, token: usedAuth ? accessToken : nil)
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as NSError where error.code == NSURLErrorCancelled {
                // Отмену (только при смене пространства) повтором не лечим.
                throw error
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let duration = Date().timeIntervalSince(started)

            // 401/403: однократный повтор с токеном (не считаем backoff-attempt).
            if (status == 401 || status == 403) && !usedAuth,
               let token = accessToken, !token.isEmpty {
                usedAuth = true
                await log(url: url, status: status, size: data.count, duration: duration,
                          state: "auth_retry", usedAuth: false, messageId: messageId(from: key))
                attempts -= 1
                continue
            }

            await log(url: url, status: status, size: data.count, duration: duration,
                      state: "response", usedAuth: usedAuth, messageId: messageId(from: key))

            if (200...299).contains(status) {
                if data.count > Int(maxFileSize) {
                    // Файл слишком большой — показываем как ссылку.
                    return nil
                }
                return data
            }

            if status == 429 || status >= 500 {
                if attempts >= 2 {
                    throw NSError(domain: "GifLoader", code: status,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(status) after retries"])
                }
                let delay = attempts == 1 ? 2.0 : 4.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }

            if attempts >= 2 {
                throw NSError(domain: "GifLoader", code: status,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// messageId часть ключа (для лога). Ключ = "messageId|url".
    private func messageId(from key: String) -> String {
        key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func urlRequest(_ url: URL, token: String?) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = requestTimeout
        req.cachePolicy = .returnCacheDataElseLoad
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Лог только состояния: host, статус, размер, длительность. Без полных URL и текстов.
    private func log(url: URL, status: Int?, size: Int?, duration: TimeInterval,
                     state: String, usedAuth: Bool, messageId: String) {
        var fields: [String: Any] = [
            "state": state,
            "host": url.host ?? "unknown",
            "durationMs": Int(duration * 1000),
            "usedAuth": usedAuth,
        ]
        if let status { fields["status"] = status }
        if let size { fields["size"] = size }
        ReactionDiagnosticsLogger.shared.log(
            stage: "gif_load",
            messageId: messageId,
            spaceId: nil,
            createdTime: nil,
            loadedVia: "GifLoader",
            fields: fields
        )
    }

    /// Отмена всех задач загрузки (при смене пространства).
    func cancelAll() {
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
        states.removeAll()
    }

    /// Ограничение дискового кэша (~100 МБ, удаление старых).
    private func enforceDiskLimit() {
        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheDir,
                                                               includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var totalSize: UInt64 = 0
        var fileInfos: [(url: URL, date: Date, size: UInt64)] = []
        for f in files {
            let attrs = (try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]))
            let date = attrs?.contentModificationDate ?? Date.distantPast
            let size = UInt64(attrs?.fileSize ?? 0)
            totalSize += size
            fileInfos.append((f, date, size))
        }
        if totalSize <= maxDiskSize { return }
        fileInfos.sort { $0.date < $1.date }
        for info in fileInfos {
            if totalSize <= maxDiskSize { break }
            try? fileManager.removeItem(at: info.url)
            totalSize -= info.size
        }
    }

    /// Проверка, загружен ли GIF уже.
    func isLoaded(messageId: String, url: URL) -> Bool {
        let key = key(messageId: messageId, url: url)
        return states[key] == .loaded || memoryCache.object(forKey: url as NSURL) != nil
    }
}
