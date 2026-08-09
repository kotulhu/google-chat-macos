import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let accessToken: String
    var onSenderTap: ((String) -> Void)? = nil
    var mentionDisplayNames: [String: String] = [:]
    var onAttachmentLayoutChanged: (() -> Void)? = nil
    var onViewportVisible: ((String) -> Void)? = nil
    var onViewportHidden: ((String) -> Void)? = nil
    var onToggleReaction: ((String, String) async -> Void)? = nil
    
    @ObservedObject private var reactionHistory = ReactionHistoryStore.shared
    @State private var showReactionPicker = false
    
    var body: some View {
        PerfBeacon.markRareView("Render", phase: "bubbleBody", detail: "id=\(message.id.suffix(12)), len=\(message.text.count)")
        HStack {
            if message.isFromMe { Spacer() }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                if !message.isFromMe {
                    if let senderId = message.senderId {
                        Button(message.authorName) {
                            onSenderTap?(senderId)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                    } else {
                        Text(message.authorName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                

                if !message.text.isEmpty {
                    let attributedText = PerfBeacon.measureReturn("Render", phase: "attributed", minMs: 3, detail: "len=\(message.text.count)") {
                        message.text.attributedStringWithLinks(mentionDisplayNames: mentionDisplayNames)
                    }
                    Text(attributedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.isFromMe ? Color.blue.opacity(0.6) : Color(NSColor.controlBackgroundColor))
                        .foregroundColor(message.isFromMe ? .white : .primary)
                        .cornerRadius(16)
                        .textSelection(.enabled)
                        .environment(\.openURL, OpenURLAction { url in
                            NSWorkspace.shared.open(url)
                            return .handled
                        })
                        .contextMenu {
                            Button("Копировать текст") {
                                copyToClipboard()
                            }
                            Divider()
                            ForEach(reactionHistory.menuEmojis, id: \.self) { emoji in
                                Button(emoji) {
                                    toggleReaction(emoji)
                                }
                            }
                            Divider()
                            Button("Другие реакции...") {
                                showReactionPicker = true
                            }
                        }
                        .sheet(isPresented: $showReactionPicker) {
                            ReactionPickerView { emoji in
                                toggleReaction(emoji)
                                showReactionPicker = false
                            }
                        }
                }
                
                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            AttachmentRow(
                                attachment: attachment,
                                accessToken: accessToken,
                                onLayoutChanged: onAttachmentLayoutChanged
                            )
                        }
                    }
                }

                if !message.reactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.reactions) { reaction in
                                Button {
                                    toggleReaction(reaction.emoji)
                                } label: {
                                    Text("\(reaction.emoji) \(reaction.count)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(reaction.isMine ? Color.accentColor.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: 260, alignment: message.isFromMe ? .trailing : .leading)
                }
                
                Text(formatFullDate(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isFromMe { Spacer() }
        }
        .padding(.horizontal)
        .onAppear {
            onViewportVisible?(message.id)
        }
        .onDisappear {
            onViewportHidden?(message.id)
        }
    }

    private func toggleReaction(_ emoji: String) {
        Task {
            await onToggleReaction?(message.id, emoji)
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.text, forType: .string)
        print("📋 Текст скопирован")
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "'Вчера, ' HH:mm"
            return formatter.string(from: date)
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, HH:mm"
            formatter.locale = Locale(identifier: "ru_RU")
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "ru_RU")
            return formatter.string(from: date)
        }
    }
}


struct AttachmentRow: View {
    let attachment: Attachment
    let accessToken: String
    var onLayoutChanged: (() -> Void)? = nil
    @State private var imageData: Data?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if attachment.isImage {
                if let imageData, let nsImage = NSImage(data: imageData) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 500)
                            .cornerRadius(8)
                        Button("Скачать") {
                            downloadFile(from: attachment.url)
                        }
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загрузка...")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .task {
                        await loadImage()
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Не удалось загрузить")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                HStack {
                    Image(systemName: fileIcon(for: attachment.mimeType))
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(attachment.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(formatBytes(attachment.size))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Скачать") {
                        downloadFile(from: attachment.url)
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: imageData)
    }
    
    private func loadImage() async {
        let cacheKey = imageCacheKey
        if let cachedData = ImageCache.shared.get(forKey: cacheKey) {
            PerfBeacon.measure("Image", phase: "nsImageDecode", minMs: 3, detail: "cacheHit, bytes=\(cachedData.count)") {
                _ = NSImage(data: cachedData)
            }
            if let nsImage = NSImage(data: cachedData) {
                await MainActor.run {
                    self.imageData = cachedData
                    self.isLoading = false
                    self.onLayoutChanged?()
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.onLayoutChanged?()
                }
            }
            return
        }
        
        PerfBeacon.start("Image", phase: "loadImageData")
        do {
            let data = try await loadImageData()
            PerfBeacon.end("Image", phase: "loadImageData", detail: "bytes=\(data.count), key=\(cacheKey)")
            if Task.isCancelled { return }
            ImageCache.shared.set(data, forKey: cacheKey)
            PerfBeacon.measure("Image", phase: "nsImageDecode", minMs: 3, detail: "network, bytes=\(data.count)") {
                _ = NSImage(data: data)
            }
            if let nsImage = NSImage(data: data) {
                await MainActor.run {
                    self.imageData = data
                    self.isLoading = false
                    self.onLayoutChanged?()
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.onLayoutChanged?()
                }
            }
        } catch {
            PerfBeacon.end("Image", phase: "loadImageData", detail: "ERROR \(error.localizedDescription)")
            if Task.isCancelled { return }
            print("❌ Ошибка загрузки: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.onLayoutChanged?()
            }
        }
    }

    private var imageCacheKey: String {
        attachmentCacheKey
    }

    private var attachmentCacheKey: String {
        attachment.resourceName ?? attachment.name
    }

    private func loadImageData() async throws -> Data {
        var candidates: [ImageLoadCandidate] = []
        if let resourceName = attachment.resourceName,
           let mediaURL = mediaURL(forResourceName: resourceName) {
            candidates.append(ImageLoadCandidate(url: mediaURL, authorization: .bearer))
        }
        if let uploadToken = attachment.uploadToken,
           let mediaURL = mediaURL(forResourceName: uploadToken) {
            candidates.append(ImageLoadCandidate(url: mediaURL, authorization: .bearer))
        }
        if let uploadToken = attachment.uploadToken,
           let downloadURL = attachmentURL(forToken: uploadToken, urlType: "DOWNLOAD_URL") {
            candidates.append(ImageLoadCandidate(url: downloadURL, authorization: .none))
            candidates.append(ImageLoadCandidate(url: downloadURL, authorization: .bearer))
        }
        if let uploadToken = attachment.uploadToken,
           let thumbnailURL = attachmentURL(forToken: uploadToken, urlType: "THUMBNAIL_URL") {
            candidates.append(ImageLoadCandidate(url: thumbnailURL, authorization: .none))
            candidates.append(ImageLoadCandidate(url: thumbnailURL, authorization: .bearer))
        }
        if let thumbnailURL = attachment.thumbnailURL {
            candidates.append(ImageLoadCandidate(url: thumbnailURL, authorization: .none))
            candidates.append(ImageLoadCandidate(url: thumbnailURL, authorization: .bearer))
        }
        if let downloadURL = attachment.url {
            candidates.append(ImageLoadCandidate(url: downloadURL, authorization: .none))
            candidates.append(ImageLoadCandidate(url: downloadURL, authorization: .bearer))
        }
        candidates = deduplicated(candidates)
        
        var lastError: Error?
        for candidate in candidates {
            do {
                var request = URLRequest(url: candidate.url)
                if candidate.authorization == .bearer {
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { throw CancellationError() }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    print("❌ Ошибка HTTP для картинки: \((response as? HTTPURLResponse)?.statusCode ?? -1), auth: \(candidate.authorization.rawValue), url: \(candidate.url)")
                    continue
                }
                
                if NSImage(data: data) != nil {
                    return data
                }
                if let redirectedData = try await loadImageDataFromAttachmentURLResponse(data) {
                    return redirectedData
                }
                print("❌ Ответ не является изображением, auth: \(candidate.authorization.rawValue), url: \(candidate.url)")
            } catch {
                lastError = error
                print("❌ Не удалось загрузить картинку auth=\(candidate.authorization.rawValue), url=\(candidate.url): \(error)")
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }

    private struct ImageLoadCandidate {
        let url: URL
        let authorization: AuthorizationMode
    }

    private enum AuthorizationMode: String {
        case none
        case bearer
    }

    private func deduplicated(_ candidates: [ImageLoadCandidate]) -> [ImageLoadCandidate] {
        var seen = Set<String>()
        var result: [ImageLoadCandidate] = []
        for candidate in candidates {
            let key = "\(candidate.authorization.rawValue)|\(candidate.url.absoluteString)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    private func mediaURL(forResourceName resourceName: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chat.googleapis.com"
        components.path = "/v1/media/" + resourceName
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        return components.url
    }

    private func attachmentURL(forToken token: String, urlType: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chat.google.com"
        components.path = "/api/get_attachment_url"
        components.queryItems = [
            URLQueryItem(name: "url_type", value: urlType),
            URLQueryItem(name: "content_type", value: attachment.mimeType),
            URLQueryItem(name: "attachment_token", value: token),
            URLQueryItem(name: "auto", value: "true")
        ]
        return components.url
    }

    private func loadImageDataFromAttachmentURLResponse(_ data: Data) async throws -> Data? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let urlString = payload["url"] as? String
                ?? payload["downloadUrl"] as? String
                ?? payload["download_url"] as? String
            if let urlString, let url = URL(string: urlString) {
                return try await loadImageData(fromResolvedURL: url)
            }
        }
        
        guard let text = String(data: data, encoding: .utf8),
              let url = firstURL(in: text) else {
            return nil
        }
        
        return try await loadImageData(fromResolvedURL: url)
    }

    private func loadImageData(fromResolvedURL url: URL) async throws -> Data? {
        let authorizationModes: [AuthorizationMode] = url.host?.contains("googleapis.com") == true
            ? [.bearer, .none]
            : [.none, .bearer]
        
        for authorization in authorizationModes {
            var request = URLRequest(url: url)
            if authorization == .bearer {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  NSImage(data: data) != nil else {
                continue
            }
            return data
        }
        return nil
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private func downloadFile(from url: URL?) {
        let cacheKey = attachmentCacheKey
        if let cachedData = AttachmentCache.shared.get(forKey: cacheKey) {
            saveData(cachedData)
            return
        }
        
        if attachment.isImage {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = attachment.name
            savePanel.begin { response in
                if response == .OK, let saveURL = savePanel.url {
                    Task {
                        do {
                            let data = try await loadImageData()
                            AttachmentCache.shared.set(data, forKey: cacheKey)
                            try data.write(to: saveURL)
                            print("✅ Изображение сохранено: \(saveURL.lastPathComponent)")
                        } catch {
                            print("❌ Ошибка сохранения изображения: \(error)")
                        }
                    }
                }
            }
            return
        }
        
        if let resourceName = attachment.resourceName {
            downloadUsingResourceName(resourceName, cacheKey: cacheKey)
            return
        }
        
        guard let url = url else { return }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = attachment.name
        savePanel.begin { response in
            if response == .OK, let saveURL = savePanel.url {
                Task {
                    do {
                        var request = URLRequest(url: url)
                        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                        let (data, _) = try await URLSession.shared.data(for: request)
                        AttachmentCache.shared.set(data, forKey: cacheKey)
                        try data.write(to: saveURL)
                        print("✅ Файл сохранён (fallback): \(saveURL.lastPathComponent)")
                    } catch {
                        print("❌ Ошибка сохранения: \(error)")
                    }
                }
            }
        }
    }

    private func saveData(_ data: Data) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = attachment.name
        savePanel.begin { response in
            if response == .OK, let saveURL = savePanel.url {
                do {
                    try data.write(to: saveURL)
                    print("✅ Файл сохранён из кэша: \(saveURL.lastPathComponent)")
                } catch {
                    print("❌ Ошибка сохранения из кэша: \(error)")
                }
            }
        }
    }

    private func downloadUsingResourceName(_ resourceName: String, cacheKey: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = attachment.name
        savePanel.begin { response in
            if response == .OK, let saveURL = savePanel.url {
                Task {
                    let urlString = "https://chat.googleapis.com/v1/media/\(resourceName)?alt=media"
                    guard let url = URL(string: urlString) else { return }
                    
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            AttachmentCache.shared.set(data, forKey: cacheKey)
                            try data.write(to: saveURL)
                            print("✅ Файл сохранён через media API: \(saveURL.lastPathComponent), размер: \(data.count) байт")
                        } else {
                            print("❌ Ошибка HTTP при скачивании: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                        }
                    } catch {
                        print("❌ Ошибка скачивания через media API: \(error)")
                    }
                }
            }
        }
    }
    
    private func fileIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.hasPrefix("video/") {
            return "video"
        } else if mimeType.hasPrefix("audio/") {
            return "audio"
        } else if mimeType == "application/pdf" {
            return "doc.text"
        } else if mimeType.contains("word") || mimeType.contains("document") {
            return "doc"
        } else if mimeType.contains("excel") || mimeType.contains("spreadsheet") {
            return "tablecells"
        } else {
            return "doc"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
