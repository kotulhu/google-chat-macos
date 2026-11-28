import Foundation
import AppKit

/// Источник GIF, извлечённый из сообщения.
struct GifSource: Equatable {
    /// Прямая ссылка на GIF-файл.
    let url: URL
    /// Ширина из API (обычно неизвестна — nil).
    let width: CGFloat?
    /// Высота из API (обычно неизвестна — nil).
    let height: CGFloat?
    /// Идентификатор сообщения для отладки.
    let messageId: String
}

/// Разбирает Message и возвращает GifSource, если в сообщении есть GIF.
///
/// Порядок источников (по приоритету):
/// 1. `attachedGifs[].uri` — встроенный выбор GIF официального клиента (основной).
///    Одно сообщение может содержать несколько GIF — возвращаются все.
/// 2. Текст, состоящий только из ссылки на GIF (tenor / giphy / .gif).
/// 3. Вложение с `mimeType == "image/gif"`.
struct GifResolver {

    /// Извлекает все GifSource из Message. attachedGifs — основной источник;
    /// rest — запасные, используются только если attachedGifs пуст.
    static func sources(from message: Message) -> [GifSource] {
        // 1. Основной источник — attachedGifs[].uri (output-only поле API).
        let fromApi = message.attachedGifs.compactMap { gif -> GifSource? in
            guard let url = gif.url else { return nil }
            return GifSource(url: url, width: nil, height: nil, messageId: message.id)
        }
        if !fromApi.isEmpty { return fromApi }

        var result: [GifSource] = []

        // 2. Текст — только ссылка на GIF (запасной источник).
        if let url = gifLinkURL(from: message.text), message.attachments.isEmpty {
            result.append(GifSource(url: url, width: nil, height: nil, messageId: message.id))
        }

        // 3. Вложение image/gif (запасной источник).
        for attachment in message.attachments where isGifAttachment(attachment) {
            guard let url = attachment.url else { continue }
            result.append(GifSource(url: url, width: nil, height: nil, messageId: message.id))
        }

        return result
    }

    /// Первый источник (для обратной совместимости с текущими вызовами).
    static func source(from message: Message) -> GifSource? {
        sources(from: message).first
    }

    /// Проверяет, является ли вложение GIF.
    private static func isGifAttachment(_ attachment: Attachment) -> Bool {
        let mime = attachment.mimeType.lowercased()
        if mime == "image/gif" { return true }
        if mime.hasPrefix("image/") {
            let ext = (attachment.name as NSString).pathExtension.lowercased()
            if ext == "gif" { return true }
        }
        if let url = attachment.url, isGifUrl(url) { return true }
        return false
    }

    /// Возвращает URL, если текст состоит только из ссылки на GIF.
    private static func gifLinkURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), isGifUrl(url) else { return nil }
        return url
    }

    /// Проверяет, является ли URL ссылкой на GIF (tenor, giphy или .gif расширение).
    private static func isGifUrl(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        if s.contains("tenor.com") || s.contains("giphy.com") { return true }
        if (s as NSString).pathExtension.lowercased() == "gif" { return true }
        return false
    }

    /// Нужно ли скрыть текст сообщения: он пуст, либо состоит только из ссылки
    /// на один из GIF этого же сообщения (чтобы не дублировать URL в пузыре).
    static func isTextOnlyGifLink(_ message: Message) -> Bool {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Текст == uri одного из attachedGifs.
        if message.attachedGifs.contains(where: {
            $0.uri.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) { return true }
        // Текст — одиночная ссылка на GIF из запасных источников.
        return gifLinkURL(from: message.text) != nil
    }
}
