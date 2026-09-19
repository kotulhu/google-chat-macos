import Foundation

/// Generic export failure surfaced to the UI.
enum ArchiveExportError: LocalizedError {
    case empty
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return L.str("export.empty")
        case .unknown(let message):
            return message
        }
    }
}

/// Generates a self-contained "folder archive" HTML export from `ArchiveStore`:
///   export-root/
///     index.html      (or part_2.html, part_3.html, … when the history spans
///                       more than `messagesPerFile` messages)
///     attachments/    (originals/thumbnails copied from the archive, fetched
///                       from the network only when the archive misses them)
struct ArchiveBatchItem {
    let spaceId: String
    let spaceName: String
    let message: Message
}

struct ArchiveBatchSpace {
    let spaceId: String
    let spaceName: String
    let updatedAt: Date
    let messages: [Message]
}

enum ArchiveExporter {

    /// Splits the export into separate HTML files at most `messagesPerFile`
    /// messages per part (the archive folder keeps attachments in one place).
    static func export(
        spaces: [ArchiveBatchSpace],
        to root: URL,
        messagesPerFile: Int = 3000,
        fetchMissingMedia: Bool = true
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let attachmentsDir = root.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.removeItem(at: attachmentsDir)
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        guard !spaces.isEmpty else {
            throw ArchiveExportError.empty
        }

        var items: [ArchiveBatchItem] = []
        for space in spaces {
            for message in space.messages.sorted(by: { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }) {
                items.append(ArchiveBatchItem(spaceId: space.spaceId, spaceName: space.spaceName, message: message))
            }
        }

        let totalParts = max(1, (items.count + messagesPerFile - 1) / messagesPerFile)

        for part in 0..<totalParts {
            let start = part * messagesPerFile
            let end = min(start + messagesPerFile, items.count)
            let chunk = Array(items[start..<end])

            // Resolve/copy attachment media before writing HTML so every tag
            // can point at a file that actually exists.
            var resolved: [String: String?] = [:]
            for item in chunk {
                for attachment in item.message.attachments {
                    if resolved[attachment.id] != nil { continue }
                    resolved[attachment.id] = await ensureAttachment(
                        attachment,
                        attachmentsDir: attachmentsDir,
                        fetchMissing: fetchMissingMedia
                    )
                }
            }

            let html = renderHTML(
                chunk: chunk,
                partIndex: part + 1,
                totalParts: totalParts,
                spaces: spaces,
                resolved: resolved
            )
            let fileName = part == 0 ? "index.html" : "part_\(part + 1).html"
            try html.write(to: root.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }

        return root
    }

    // MARK: - Media

    private static func ensureAttachment(_ attachment: Attachment, attachmentsDir: URL, fetchMissing: Bool) async -> String? {
        let id = attachment.id
        if let stored = ArchiveStore.shared.mediaStoredName(attachmentId: id) {
            let dest = attachmentsDir.appendingPathComponent(stored)
            if !FileManager.default.fileExists(atPath: dest.path),
               let data = ArchiveStore.shared.mediaData(storedName: stored) {
                try? data.write(to: dest, options: [.atomic])
            }
            return stored
        }

        guard fetchMissing, let url = attachment.url ?? attachment.thumbnailURL else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else { return nil }
            let stored = ArchiveStore.shared.storeMedia(
                data: data,
                attachmentId: id,
                mimeType: attachment.mimeType,
                originalName: attachment.name
            )
            if let stored {
                let dest = attachmentsDir.appendingPathComponent(stored)
                try? data.write(to: dest, options: [.atomic])
            }
            return stored
        } catch {
            return nil
        }
    }

    // MARK: - HTML

    private static func renderHTML(
        chunk: [ArchiveBatchItem],
        partIndex: Int,
        totalParts: Int,
        spaces: [ArchiveBatchSpace],
        resolved: [String: String?]
    ) -> String {
        let dateString = timestampFormatter().string(from: Date())
        var body = ""

        body += renderHeader(partIndex: partIndex, totalParts: totalParts, dateString: dateString, spaces: spaces)

        var currentSpace: String?
        var spaceIndex = 0
        for item in chunk {
            if item.spaceId != currentSpace {
                currentSpace = item.spaceId
                spaceIndex += 1
                if let space = spaces.first(where: { $0.spaceId == item.spaceId }) {
                    body += renderSpaceHeader(space, index: spaceIndex)
                }
            }
            body += renderMessage(item, resolved: resolved)
        }

        body += renderNav(partIndex: partIndex, totalParts: totalParts)

        return """
        <!DOCTYPE html>
        <html lang="\(L.isRussian ? "ru" : "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Gogol Chat">
        <title>\(escapeHTML(L.str("export.doc.title")))</title>
        <style>
        \(css())
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>
        """
    }

    private static func renderHeader(partIndex: Int, totalParts: Int, dateString: String, spaces: [ArchiveBatchSpace]) -> String {
        var html = """
        <h1>\(escapeHTML(L.str("export.doc.title")))</h1>
        <p class="meta">\(escapeHTML(L.str("export.doc.exported", dateString)))</p>
        """
        if totalParts > 1 {
            html += renderPartTOC(partIndex: partIndex, totalParts: totalParts)
        } else {
            var tocRows = ""
            for (index, space) in spaces.enumerated() {
                let label = L.str("export.doc.messages", String(space.messages.count))
                tocRows += "<li><a href=\"#space-\(index + 1)\">\(escapeHTML(space.spaceName))</a> <span class=\"muted\">— \(escapeHTML(label))</span></li>"
            }
            if !tocRows.isEmpty {
                html += "<nav class=\"toc\"><h2>\(escapeHTML(L.str("export.doc.toc")))</h2><ul>\(tocRows)</ul></nav>"
            }
        }
        return html
    }

    private static func renderPartTOC(partIndex: Int, totalParts: Int) -> String {
        var links = ""
        for part in 1...totalParts {
            let current = part == partIndex
            let href = part == 1 ? "index.html" : "part_\(part).html"
            let label = current ? "<b>\(part)</b>" : "\(part)"
            links += "<a class=\"part-link\" href=\"\(href)\">\(label)</a>"
        }
        return "<nav class=\"toc\"><h2>\(escapeHTML(L.str("export.doc.part", String(partIndex), String(totalParts))))</h2><div class=\"part-bar\">\(links)</div></nav>"
    }

    private static func renderSpaceHeader(_ space: ArchiveBatchSpace, index: Int) -> String {
        let count = L.str("export.doc.messages", String(space.messages.count))
        let updated = L.str("export.doc.messages.updated", timestampFormatter().string(from: space.updatedAt))
        return """
        <section class="space">
        <h2 id="space-\(index)">\(escapeHTML(space.spaceName))</h2>
        <p class="meta">\(escapeHTML(count)) · \(escapeHTML(updated))</p>
        </section>
        """
    }

    private static func renderMessage(_ item: ArchiveBatchItem, resolved: [String: String?]) -> String {
        let message = item.message
        var inner = ""
        inner += "<div class=\"msg-head\"><span class=\"author state-\(message.isFromMe ? "mine" : "theirs")\">\(escapeHTML(message.authorName))</span><span class=\"time\">\(escapeHTML(timestampFormatter().string(from: message.timestamp)))</span></div>"

        if let quote = message.quotedMessage, !quote.messageId.isEmpty {
            let sayer = quote.authorName ?? L.str("export.doc.quote")
            let qt = quote.text ?? ""
            inner += "<blockquote class=\"quote\"><span class=\"qsrc\">\(escapeHTML(sayer))</span><p>\(escapeHTML(quoteText(qt)))</p></blockquote>"
        }

        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inner += "<div class=\"body\">\(linkifiedHTML(message.text))</div>"
        }

        if !message.attachments.isEmpty {
            var rows = ""
            for attachment in message.attachments {
                rows += renderAttachment(attachment, storedName: resolved[attachment.id] ?? nil)
            }
            inner += "<div class=\"attachments\">\(rows)</div>"
        }

        if !message.reactions.isEmpty {
            let counts = message.reactions.map { reaction in
                "<span class=\"reaction\">\(escapeHTML(reaction.emoji)) <b>\(reaction.count)</b></span>"
            }.joined(separator: " ")
            inner += "<div class=\"reactions\">\(counts)</div>"
        }

        return "<article class=\"msg\">\(inner)</article>"
    }

    private static func renderAttachment(_ attachment: Attachment, storedName: String?) -> String {
        let name = escapeHTML(attachment.name)
        let size = attachment.size > 0 ? formatBytes(attachment.size) : ""
        let caption = size.isEmpty ? name : "\(name) — \(size)"

        if let storedName {
            let localRef = localHREF(storedName)
            switch kind(of: attachment) {
            case .image:
                return """
                <figure class="attachment">
                <a href="\(localRef)" target="_blank"><img loading="lazy" src="\(localRef)" alt="\(name)"></a>
                <figcaption>\(caption)</figcaption>
                </figure>
                """
            case .video:
                return """
                <figure class="attachment video">
                <video controls preload="metadata" src="\(localRef)"><a href="\(localRef)">\(caption)</a></video>
                <figcaption>\(caption)</figcaption>
                </figure>
                """
            case .file:
                return """
                <p class="attachment file"><a href="\(localRef)" download>📎 \(caption)</a></p>
                """
            }
        }

        if let url = attachment.url?.absoluteString ?? attachment.thumbnailURL?.absoluteString {
            let hint = L.str("export.link.original")
            return """
            <p class="attachment file"><a class="ext" href="\(escapeHTML(url))" target="_blank">🔗 \(caption) <span class="muted">(\(escapeHTML(hint)))</span></a></p>
            """
        }

        return "<p class=\"attachment missing\">\(caption) <span class=\"muted\">(\(escapeHTML(L.str("export.missing"))))</span></p>"
    }

    private static func renderNav(partIndex: Int, totalParts: Int) -> String {
        guard totalParts > 1 else { return "" }
        var links = ""
        if partIndex > 1 {
            let href = partIndex == 2 ? "index.html" : "part_\(partIndex - 1).html"
            links += "<a href=\"\(href)\">← \(escapeHTML(L.str("export.doc.prev")))</a>"
        }
        if partIndex < totalParts {
            let href = "part_\(partIndex + 1).html"
            links += "&nbsp;·&nbsp;<a href=\"\(href)\">\(escapeHTML(L.str("export.doc.next"))) →</a>"
        }
        return "<nav class=\"pager\">\(links)</nav>"
    }

    // MARK: - Text helpers

    private static func linkifiedHTML(_ text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsText = text as NSString
        var matches: [NSTextCheckingResult] = []
        detector?.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            if let match { matches.append(match) }
        }
        matches.sort { $0.range.location < $1.range.location }

        var html = ""
        var cursor = 0
        for match in matches {
            if match.range.location < cursor { continue }
            let plain = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            html += escapeHTML(plain).replacingOccurrences(of: "\n", with: "<br>")
            let url = match.url?.absoluteString ?? nsText.substring(with: match.range)
            html += "<a href=\"\(escapeHTML(url))\">\(escapeHTML(url))</a>"
            cursor = match.range.location + match.range.length
        }
        html += escapeHTML(nsText.substring(from: cursor)).replacingOccurrences(of: "\n", with: "<br>")
        return html
    }

    private static func quoteText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private static func localHREF(_ storedName: String) -> String {
        "attachments/\(escapeHTML(storedName))"
    }

    private enum AttachmentKind {
        case image, video, file
    }

    private static func kind(of attachment: Attachment) -> AttachmentKind {
        guard !attachment.mimeType.hasPrefix("image/") else { return .image }
        if attachment.mimeType.hasPrefix("video/") { return .video }
        let ext = URL(fileURLWithPath: attachment.name).pathExtension.lowercased()
        let imageExts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"]
        let videoExts = ["mp4", "mov", "m4v", "webm", "avi", "mkv"]
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        return .file
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func escapeHTML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    private static func timestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.isRussian ? "ru_RU" : "en_US")
        formatter.dateFormat = L.isRussian ? "d MMMM yyyy, HH:mm" : "MMM d, yyyy, HH:mm"
        return formatter
    }

    // MARK: - CSS

    private static func css() -> String {
        """
        :root {
          --bg: #f7f7f8; --fg: #1b1b1f; --muted: #6b6b73; --bubble: #ffffff;
          --accent: #2962ff; --border: #e3e3e8; --quote: #ececf1;
        }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #1e1e22; --fg: #ededf0; --muted: #9b9ba6; --bubble: #2a2a30;
                  --accent: #7aa2ff; --border: #3a3a42; --quote: #38383f; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--fg);
               font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
        main { max-width: 860px; margin: 0 auto; padding: 24px 20px 60px; }
        h1 { font-size: 24px; margin: 8px 0 2px; }
        h2 { font-size: 18px; margin: 28px 0 8px; }
        .meta, .muted { color: var(--muted); }
        .meta { font-size: 13px; margin: 4px 0 8px; }
        nav.toc, nav.pager { background: var(--bubble); border: 1px solid var(--border);
                             border-radius: 10px; padding: 12px 16px; margin: 16px 0; }
        nav.toc ul { margin: 8px 0 0; padding-left: 20px; }
        .part-bar { margin-top: 8px; display: flex; gap: 6px; flex-wrap: wrap; }
        .part-link { color: var(--accent); text-decoration: none; padding: 2px 8px; }
        .part-link b { color: var(--fg); }
        section.space { margin-top: 8px; border-bottom: 1px solid var(--border); padding-bottom: 4px; }
        article.msg { background: var(--bubble); border: 1px solid var(--border); border-radius: 10px;
                      padding: 10px 14px; margin: 10px 0; }
        .msg-head { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
        .author { font-weight: 600; }
        .state-mine { color: var(--accent); }
        .time { color: var(--muted); font-size: 12px; }
        .body { margin-top: 4px; white-space: normal; overflow-wrap: break-word; }
        .body a, .attachment a, .ext { color: var(--accent); text-decoration: none; }
        .body a:hover, .attachment a:hover { text-decoration: underline; }
        blockquote.quote { margin: 8px 0; padding: 8px 12px; background: var(--quote);
                           border-left: 3px solid var(--accent); border-radius: 6px; }
        blockquote.quote .qsrc { display: block; font-size: 12px; font-weight: 600; color: var(--muted); }
        blockquote.quote p { margin: 2px 0 0; color: var(--muted); overflow-wrap: break-word; }
        .attachments { margin-top: 8px; }
        .attachment { margin: 8px 0; }
        figure.attachment { margin: 0 0 12px; }
        figure.attachment img { max-width: 100%; max-height: 420px; border-radius: 8px; display: block; }
        figure.attachment video { max-width: 100%; max-height: 420px; border-radius: 8px; display: block; }
        figcaption { font-size: 12px; color: var(--muted); margin-top: 4px; }
        p.attachment.file a { font-size: 14px; }
        .reactions { margin-top: 6px; font-size: 13px; display: flex; gap: 6px; flex-wrap: wrap; }
        .reaction { background: var(--quote); padding: 2px 8px; border-radius: 20px; }
        nav.pager { text-align: center; }
        nav.pager a { color: var(--accent); text-decoration: none; }
        """
    }
}