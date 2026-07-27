import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ChatViewModel: NSObject,ObservableObject {
    @Published var spaces: [ChatSpace] = []
    @Published var messages: [Message] = []
    @Published var selectedSpace: ChatSpace?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentSpaceMembers: [ChatUser] = []
    
    private var chatService: GoogleChatService?
    
    private var pollTimer: Timer?
    
    private var tokenRefreshTimer: Timer?
    private let defaults = UserDefaults.standard
    private let lastReadKeyPrefix = "lastRead_"
    private var backgroundTimer: Timer?
    
    
    @Published private(set) var accessToken: String = ""
    
    private var sentNotificationIds = Set<String>()
    
    private var backgroundCheckTimer: Timer?
    
    private var userEmailCache: [String: String] = [:]
    private var memberCache: [String: [ChatUser]] = [:]
    private var reactionCache: [String: [MessageReaction]] = [:]
    private var loadingReactionMessageIds = Set<String>()
    private var userNameCache: [String: String] = [:]
    private let cacheDefaults = UserDefaults.standard
    private let userNameCacheKey = "userNameCache"
    
    private let mappingKey = "directChatUserMapping"
    private var directChatUserMapping: [String: String] = [:]
    
    private var currentUserId: String = ""
    private var currentUserEmail: String = ""
    private var currentUserName: String = ""

    private lazy var reactionViewportController = ViewportRefreshController { [weak self] messageId in
        await self?.loadReactions(for: messageId)
    }

    override init() {
        super.init()
        
        loadCache()
        loadMapping()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localDisplayNameDidChange),
            name: ConfigManager.localDisplayNameDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func localDisplayNameDidChange() {
        currentUserName = ConfigManager.shared.localDisplayName
        chatService?.updateCurrentUser(name: currentUserDisplayName)
        
        for index in messages.indices where messages[index].isFromMe {
            messages[index].authorName = currentUserDisplayName
        }
        objectWillChange.send()
    }
    func setCurrentUserId() async {
        do {
            let peopleId = try await chatService?.fetchCurrentUserId() ?? ""
            currentUserId = peopleId.replacingOccurrences(of: "people/", with: "users/")
            chatService?.updateCurrentUser(id: currentUserId)
            print("✅ Текущий пользователь ID: \(currentUserId)")
        } catch {
            print("❌ Не удалось получить ID текущего пользователя: \(error)")
        }
    }
    
    private func loadMapping() {
        directChatUserMapping = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        print("DEBUG: mapping loaded from UserDefaults: \(directChatUserMapping)")
    }

    private func saveMapping() {
        let currentMapping = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        if currentMapping != directChatUserMapping {
            defaults.set(directChatUserMapping, forKey: mappingKey)
            print("DEBUG: mapping saved (только при изменении)")
        }
    }
    
    private func loadCache() {
        userNameCache = cacheDefaults.dictionary(forKey: userNameCacheKey) as? [String: String] ?? [:]
        print("DEBUG: user name cache loaded: \(userNameCache)")
    }

    private func saveCache() {
        cacheDefaults.set(userNameCache, forKey: userNameCacheKey)
    }

    func fetchCurrentUserId() async {
        guard let service = chatService else { return }
        do {
            currentUserId = try await service.fetchCurrentUserId()
            currentUserId = currentUserId.replacingOccurrences(of: "people/", with: "users/")
            chatService?.updateCurrentUser(id: currentUserId)
            print("✅ Текущий пользователь ID: \(currentUserId)")
        } catch {
            print("❌ Ошибка получения ID: \(error)")
        }
        await refreshDirectChatMappingsAndNames()
    }
    
    func startTokenRefreshTimer(authManager: GoogleAuthManager) {
        tokenRefreshTimer?.invalidate()
        print("⏰ Запуск таймера обновления токена (каждые 50 минут)")
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 50 * 60, repeats: true) { _ in
            print("🔄 Таймер сработал, обновляем токен...")
            Task {
                let success = await authManager.refreshAccessToken()
                if success {
                    await MainActor.run {
                        let token = authManager.accessToken
                        print("✅ Токен обновлён, новый токен: \(token.prefix(50))...")
                        self.accessToken = token
                        self.chatService?.updateToken(token)
                    }
                } else {
                    print("❌ Не удалось обновить токен")
                }
            }
        }
    }

    func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    func startPolling(for space: ChatSpace) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let currentSpace = self.selectedSpace, currentSpace.id == space.id else { return }
            Task {
                await self.loadMessages(for: space)
            }
        }
        reactionViewportController.start()
        print("🔄 [Poll] startPolling for: \(space.name), backgroundCheckTimer=\(backgroundCheckTimer != nil ? "running" : "NOT running")")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        reactionViewportController.stop()
        print("🛑 Остановка polling")
    }
    
    func configure(with token: String, authManager: GoogleAuthManager) {
        self.accessToken = token
        self.currentUserEmail = authManager.userEmail
        self.currentUserName = ConfigManager.shared.localDisplayName.isEmpty
            ? authManager.userName
            : ConfigManager.shared.localDisplayName
        self.chatService = GoogleChatService(
            accessToken: token,
            authManager: authManager,
            currentUserEmail: authManager.userEmail,
            currentUserName: currentUserName
        )
        print("🔧 ChatViewModel сконфигурирован")
        
        sentNotificationIds.removeAll()
        print("🧹 sentNotificationIds очищен")
        Task {
            await setCurrentUserId()
        }
        
        startBackgroundRefresh()
    }
    
    func loadSpaces() async {
        print("📡 loadSpaces() начат")
        guard let service = chatService else {
            print("❌ chatService = nil (токен не передан)")
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedSpaces = try await service.fetchSpaces()
            
            print("✅ Получено \(fetchedSpaces.count) чатов")
            self.spaces = fetchedSpaces
            startBackgroundCheck()

            if currentUserId.isEmpty {
                await fetchCurrentUserId()
            }
            
            await refreshDirectChatMappingsAndNames()
            
            self.objectWillChange.send()
            
            await refreshUnreadCounts()

            print("🔧 [Diag] spaces=\(spaces.count), bgTimer=\(backgroundCheckTimer != nil ? "YES" : "NO"), service=\(chatService != nil ? "YES" : "NO")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                print("🔧 [Diag+5s] spaces=\(self.spaces.count), bgTimer=\(self.backgroundCheckTimer != nil ? "YES" : "NO"), selected=\(self.selectedSpace?.name ?? "none")")
                Task { await self.checkAllSpacesForNewMessages() }
            }
            if let first = fetchedSpaces.first {
                self.selectedSpace = first
                await loadMessages(for: first)
            }
        } catch {
            errorMessage = "Ошибка загрузки чатов: \(error.localizedDescription)"
            print("❌ \(errorMessage!)")
        }
    }
    
    func refreshUnreadCounts() async {
        guard let service = chatService else { return }
        await withTaskGroup(of: (String, Message?).self) { group in
            for space in spaces {
                group.addTask {
                    do {
                        let messages = try await service.fetchMessages(spaceId: space.id, pageSize: 1)
                        return (space.id, messages.first)
                    } catch {
                        return (space.id, nil)
                    }
                }
            }
            for await (spaceId, lastMessage) in group {
                if let index = spaces.firstIndex(where: { $0.id == spaceId }) {
                    if let lastRead = loadLastReadTimestamp(for: spaceId) {
                        if let lastMessage = lastMessage, !lastMessage.isFromMe, lastMessage.timestamp > lastRead {
                            spaces[index].unreadCount = 1
                        } else {
                            spaces[index].unreadCount = 0
                        }
                    } else {
                        if let lastMessage = lastMessage, !lastMessage.isFromMe {
                            spaces[index].unreadCount = 1
                        } else {
                            spaces[index].unreadCount = 0
                        }
                    }
                }
            }
        }
        updateDockBadge()
    }
    
    func startBackgroundRefresh() {
        backgroundTimer?.invalidate()
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshUnreadCounts() }
        }
    }

    func stopBackgroundRefresh() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }
    
    func getUserNameSync(userId: String) -> String {
        if let cached = userNameCache[userId], isUsablePersonName(cached) {
            return cached
        }
        userNameCache.removeValue(forKey: userId)
        let shortId = userId.replacingOccurrences(of: "users/", with: "").suffix(6)
        return "User \(shortId)"
    }
    
    func loadMessages(for space: ChatSpace) async {
        guard let service = chatService else { return }
        isLoading = true
        defer { isLoading = false }
        
        let cachedMessages = MessageCache.shared.get(spaceId: space.id)
        if let cachedMessages, !cachedMessages.isEmpty {
            for message in cachedMessages where !message.reactions.isEmpty {
                reactionCache[message.id] = message.reactions
            }
            self.messages = normalizeMessagesForDisplay(cachedMessages)
        }
        
        do {
            let fetchedMessages = try await service.fetchMessages(spaceId: space.id)
            accessToken = service.currentAccessToken
            
            if space.type == .direct {
                await refreshDirectChatMappingAndName(for: space)
            }
            
            var messagesWithNames: [Message] = []
            for var msg in fetchedMessages {
                if let senderId = msg.senderId, !msg.isFromMe {
                    msg.authorName = getUserName(userId: senderId)
                } else {
                    msg.authorName = currentUserDisplayName
                }
                if let cachedReactions = reactionCache[msg.id] {
                    msg.reactions = cachedReactions
                }
                messagesWithNames.append(msg)
            }
            if self.messages != messagesWithNames {
                self.messages = messagesWithNames
            }
            MessageCache.shared.set(messagesWithNames, forSpaceId: space.id)
            
        } catch {
            if cachedMessages?.isEmpty != false {
                errorMessage = "Ошибка загрузки сообщений: \(error.localizedDescription)"
                print("❌ \(errorMessage!)")
            } else {
                print("⚠️ Не удалось обновить сообщения из сети, показан кэш: \(error)")
            }
        }
    }

    private func normalizeMessagesForDisplay(_ messages: [Message]) -> [Message] {
        messages.map { message in
            guard message.authorName.trimmingCharacters(in: .whitespacesAndNewlines) == "Native Mac Client" else {
                return message
            }
            
            return Message(
                id: message.id,
                text: message.text,
                authorName: currentUserDisplayName,
                isFromMe: true,
                timestamp: message.timestamp,
                attachments: message.attachments,
                senderId: nil,
                reactions: message.reactions
            )
        }
    }
    
    @discardableResult
    func sendMessage(_ text: String) async -> Bool {
        guard let service = chatService, let space = selectedSpace else { return false }
        do {
            try await service.sendMessage(spaceId: space.id, text: text)
            await loadMessages(for: space)
            return true
        } catch {
            errorMessage = "Ошибка отправки: \(error.localizedDescription)"
            print("❌ \(errorMessage!)")
            return false
        }
    }
    
    func clearData() {
        spaces = []
        messages = []
        selectedSpace = nil
        chatService = nil
        errorMessage = nil
        isLoading = false
        sentNotificationIds.removeAll()
        stopPolling()
        stopTokenRefreshTimer()
        stopBackgroundCheck()
        directChatUserMapping.removeAll()
        reactionCache.removeAll()
        loadingReactionMessageIds.removeAll()
        updateDockBadge()
        print("🧹 Данные очищены")
    }
    

    func getUserName(userId: String) -> String {
        if let cached = userNameCache[userId], isUsablePersonName(cached) {
            return cached
        }
        userNameCache.removeValue(forKey: userId)
        
        let shortId = userId.replacingOccurrences(of: "users/", with: "").suffix(6)
        let fallback = "User \(shortId)"
        
        Task {
            if userNameCache[userId] != nil { return }
            
            let realName = await fetchUserRealName(userId: userId)
            if realName != fallback {
                userNameCache[userId] = realName
                saveCache()
                await MainActor.run {
                    for i in self.messages.indices {
                        if self.messages[i].senderId == userId {
                            self.messages[i].authorName = realName
                        }
                    }
                    self.objectWillChange.send()
                }
            }
        }
        
        return fallback
    }

    private var currentUserDisplayName: String {
        let localDisplayName = ConfigManager.shared.localDisplayName
        if isUsablePersonName(localDisplayName) {
            return localDisplayName
        }
        if isUsablePersonName(currentUserName) {
            return currentUserName
        }
        if !currentUserEmail.isEmpty {
            return currentUserEmail
        }
        if !currentUserId.isEmpty {
            return currentUserId
        }
        return "Native Mac Client"
    }

    private func isUsablePersonName(_ name: String?) -> Bool {
        guard let name else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != "Native Mac Client" && trimmed != "Пользователь"
    }
    
    private func fetchUserRealName(userId: String) async -> String {
        do {
            let name = try await chatService?.fetchUserNameViaChatAPI(userId: userId) ?? ""
            if isUsablePersonName(name) {
                print("✅ Имя из Chat API: \(name) для \(userId)")
                return name
            }
        } catch {
            print("⚠️ Chat API не дал имя для \(userId): \(error)")
        }

        do {
            let email = try await chatService?.fetchUserEmail(userId: userId) ?? ""
            if !email.isEmpty {
                return email
            }
        } catch {
            print("⚠️ People API не дал email для \(userId): \(error)")
        }

        let shortId = userId.replacingOccurrences(of: "users/", with: "").suffix(6)
        return "User \(shortId)"
    }
    
    func uploadFile(fileURL: URL, to spaceId: String) async throws -> String {
        guard let service = chatService else { throw NSError(domain: "Chat", code: 0, userInfo: [NSLocalizedDescriptionKey: "Service not configured"]) }
        return try await service.uploadFile(fileURL: fileURL, to: spaceId)
    }

    func createSpace(name: String, type: ChatSpace.SpaceType) async -> Bool {
        guard let service = chatService else { return false }
        do {
            let created = try await service.createSpace(name: name, type: type)
            spaces.insert(created, at: 0)
            selectedSpace = created
            await loadMessages(for: created)
            return true
        } catch {
            errorMessage = "Ошибка создания чата: \(error.localizedDescription)"
            print("❌ \(errorMessage!)")
            return false
        }
    }

    func openDirectChat(with userId: String) async {
        guard let service = chatService else { return }
        
        for space in spaces where space.type == .direct {
            if directChatUserMapping[space.id] == userId {
                selectedSpace = space
                await loadMessages(for: space)
                return
            }
            
            if let members = try? await service.fetchSpaceMembers(spaceId: space.id),
               members.contains(userId) {
                directChatUserMapping[space.id] = userId
                saveMapping()
                selectedSpace = space
                await loadMessages(for: space)
                return
            }
        }
        
        do {
            let created = try await service.createDirectChat(with: userId)
            spaces.insert(created, at: 0)
            directChatUserMapping[created.id] = userId
            saveMapping()
            selectedSpace = created
            await loadMessages(for: created)
        } catch {
            errorMessage = "Ошибка открытия личного чата: \(error.localizedDescription)"
            print("❌ \(errorMessage!)")
        }
    }

    func loadMembers(for spaceId: String) async {
        if let cached = memberCache[spaceId] {
            if selectedSpace?.id == spaceId {
                currentSpaceMembers = cached
            }
            return
        }
        
        guard let service = chatService else { return }
        do {
            let members = try await service.fetchSpaceMemberUsers(spaceId: spaceId)
            let enrichedMembers = await enrichUsersWithEmails(members)
            memberCache[spaceId] = enrichedMembers
            if selectedSpace?.id == spaceId {
                currentSpaceMembers = enrichedMembers
            }
        } catch {
            print("❌ Ошибка загрузки участников: \(error)")
            if selectedSpace?.id == spaceId {
                currentSpaceMembers = []
            }
        }
    }

    private func enrichUsersWithEmails(_ users: [ChatUser]) async -> [ChatUser] {
        var result: [ChatUser] = []
        for user in users {
            if let email = user.email, !email.isEmpty {
                userEmailCache[user.id] = email
                result.append(user)
                continue
            }
            
            if let cachedEmail = userEmailCache[user.id], !cachedEmail.isEmpty {
                result.append(ChatUser(id: user.id, email: cachedEmail, displayName: user.displayName, avatarURL: user.avatarURL))
                continue
            }
            
            do {
                let email = try await chatService?.fetchUserEmail(userId: user.id) ?? ""
                if !email.isEmpty {
                    userEmailCache[user.id] = email
                    result.append(ChatUser(id: user.id, email: email, displayName: user.displayName, avatarURL: user.avatarURL))
                    continue
                }
            } catch {
                print("⚠️ Не удалось получить email для \(user.id): \(error)")
            }
            
            result.append(user)
        }
        return result
    }

    @discardableResult
    func sendMessage(_ text: String, attachments: [String] = []) async -> Bool {
        guard let service = chatService, let space = selectedSpace else { return false }
        do {
            if attachments.isEmpty {
                try await service.sendMessage(spaceId: space.id, text: text)
            } else {
                try await service.sendMessageWithAttachments(spaceId: space.id, text: text, attachmentUploadTokens: attachments)
            }
            await loadMessages(for: space)
            return true
        } catch {
            errorMessage = "Ошибка отправки: \(error.localizedDescription)"
            print("❌ \(errorMessage!)")
            return false
        }
    }

    func markReactionViewportVisible(id: String) {
        reactionViewportController.markVisible(id: id)
    }

    func markReactionViewportHidden(id: String) {
        reactionViewportController.markHidden(id: id)
    }

    func loadReactions(for messageId: String) async {
        if let cached = reactionCache[messageId] {
            applyReactions(cached, to: messageId)
            return
        }
        guard !loadingReactionMessageIds.contains(messageId), let service = chatService else {
            return
        }
        
        loadingReactionMessageIds.insert(messageId)
        defer { loadingReactionMessageIds.remove(messageId) }
        
        do {
            let reactions = try await service.fetchReactions(messageId: messageId)
            reactionCache[messageId] = reactions
            applyReactions(reactions, to: messageId)
        } catch {
            guard !isCancellation(error) else {
                return
            }
            print("❌ Ошибка загрузки реакций для \(messageId): \(error)")
        }
    }

    func toggleReaction(messageId: String, emoji: String) async {
        guard let service = chatService,
              let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        let oldReactions = messages[index].reactions
        let hasMyReaction = oldReactions.first { $0.emoji == emoji && $0.isMine }
        applyReactions(toggledReactions(oldReactions, emoji: emoji), to: messageId)
        
        do {
            if let reactionName = hasMyReaction?.myReactionName {
                try await service.removeReaction(reactionId: reactionName)
            } else if hasMyReaction != nil {
                let freshReactions = try await service.fetchReactions(messageId: messageId)
                reactionCache[messageId] = freshReactions
                guard let reactionName = freshReactions.first(where: { $0.emoji == emoji && $0.isMine })?.myReactionName else {
                    applyReactions(freshReactions, to: messageId)
                    return
                }
                try await service.removeReaction(reactionId: reactionName)
            } else {
                _ = try await service.addReaction(messageId: messageId, emoji: emoji)
            }
            
            let reactions = try await service.fetchReactions(messageId: messageId)
            reactionCache[messageId] = reactions
            applyReactions(reactions, to: messageId)
        } catch {
            guard !isCancellation(error) else {
                reactionCache[messageId] = oldReactions
                applyReactions(oldReactions, to: messageId)
                return
            }
            print("❌ Ошибка изменения реакции \(emoji) для \(messageId): \(error)")
            reactionCache[messageId] = oldReactions
            applyReactions(oldReactions, to: messageId)
        }
    }

    private func applyReactions(_ reactions: [MessageReaction], to messageId: String) {
        reactionCache[messageId] = reactions
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].reactions = reactions
            objectWillChange.send()
        }
    }

    private func toggledReactions(_ reactions: [MessageReaction], emoji: String) -> [MessageReaction] {
        let myId = currentUserId.isEmpty ? "users/me" : currentUserId
        var result = reactions
        if let index = result.firstIndex(where: { $0.emoji == emoji }) {
            if result[index].isMine {
                result[index].isMine = false
                result[index].myReactionName = nil
                result[index].userIds.removeAll { $0 == myId || $0 == "users/me" }
                result[index].reactionNamesByUserId.removeValue(forKey: myId)
                result[index].reactionNamesByUserId.removeValue(forKey: "users/me")
                if result[index].userIds.isEmpty {
                    result.remove(at: index)
                }
            } else {
                result[index].isMine = true
                if !result[index].userIds.contains(myId) {
                    result[index].userIds.append(myId)
                    result[index].userIds.sort()
                }
            }
        } else {
            result.append(MessageReaction(
                emoji: emoji,
                userIds: [myId],
                reactionNamesByUserId: [:],
                isMine: true,
                myReactionName: nil
            ))
        }
        return result.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.emoji < rhs.emoji
            }
            return lhs.count > rhs.count
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
    
    func lastReadMessageId(in messages: [Message]) -> String? {
        guard let space = selectedSpace else { return nil }
        let lastRead = space.lastReadTimestamp ?? Date()
        if let candidate = messages.last(where: { $0.timestamp <= lastRead }) {
            return candidate.id
        }
        return messages.last?.id
    }
    
    func initialScrollTarget(for spaceId: String) -> (id: String, anchor: UnitPoint)? {
        if let lastRead = loadLastReadTimestamp(for: spaceId) {
            if let firstUnread = messages.reversed().first(where: { !$0.isFromMe && $0.timestamp > lastRead }) {
                return (firstUnread.id, .top)
            }
        } else if let firstUnread = messages.reversed().first(where: { !$0.isFromMe }) {
            return (firstUnread.id, .top)
        }
        return messages.first.map { ($0.id, .bottom) }
    }
    
    func markMessageAsRead(_ message: Message, in spaceId: String) {
        guard !message.isFromMe else { return }
        
        let currentLastRead = loadLastReadTimestamp(for: spaceId)
        if let currentLastRead, message.timestamp <= currentLastRead {
            return
        }
        
        saveLastReadTimestamp(for: spaceId, date: message.timestamp)
        
        if let index = spaces.firstIndex(where: { $0.id == spaceId }) {
            spaces[index].lastReadTimestamp = message.timestamp
            let hasUnreadAfterVisibleMessage = messages.contains {
                !$0.isFromMe && $0.timestamp > message.timestamp
            }
            spaces[index].unreadCount = hasUnreadAfterVisibleMessage ? 1 : 0
        }
        updateDockBadge()
    }
    
    func saveLastReadTimestamp(for spaceId: String, date: Date) {
        defaults.set(date, forKey: lastReadKeyPrefix + spaceId)
        print("DEBUG: mapping saved: \(directChatUserMapping)")
    }

    private func loadLastReadTimestamp(for spaceId: String) -> Date? {
        return defaults.object(forKey: lastReadKeyPrefix + spaceId) as? Date
    }
    
    func sendMessageAndScroll(_ text: String) async {
        await sendMessage(text)
        await MainActor.run {
            objectWillChange.send()
        }
    }
    private func sendNotification(for message: Message, in space: ChatSpace) {
        guard !message.isFromMe else { return }

        let content = UNMutableNotificationContent()
        content.title = space.name
        content.body = "\(message.authorName): \(message.text)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        print("🔔 [Notify] sending: \"\(space.name)\" — \(message.authorName): \(message.text.prefix(40))")
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 [Notify] ERROR: \(error.localizedDescription)")
            } else {
                print("🔔 [Notify] OK id=\(request.identifier)")
            }
        }
    }
    
    func checkAllSpacesForNewMessages() async {
        print("🟢 [Check] START: spaces=\(spaces.count), selected=\(selectedSpace?.name ?? "nil"), dedup=\(sentNotificationIds.count)")
        guard let service = chatService else {
            print("🟢 [Check] ABORT: chatService=nil")
            return
        }
        
        for space in spaces {
            if selectedSpace?.id == space.id { continue }
            
            do {
                let latestMessages = try await service.fetchMessages(spaceId: space.id, pageSize: 1)
                guard let lastMessage = latestMessages.first else { continue }
                
                guard !lastMessage.isFromMe else { continue }
                
                var lastRead = loadLastReadTimestamp(for: space.id)
                if let readDate = lastRead, readDate.timeIntervalSince1970 < 1000000000 {
                    lastRead = nil
                }
                let actualLastRead = lastRead ?? Date()
                if lastRead == nil {
                    saveLastReadTimestamp(for: space.id, date: actualLastRead)
                }

                let isNew = lastMessage.timestamp > actualLastRead
                print("🟢 [Check] \(space.name): msg=\(lastMessage.timestamp), lastRead=\(actualLastRead), new=\(isNew), isMe=\(lastMessage.isFromMe)")
                
                if isNew {
                    let messageId = "\(space.id)_\(lastMessage.timestamp.timeIntervalSince1970)"
                    
                    if sentNotificationIds.contains(messageId) {
                        print("🟢 [Check] \(space.name): SKIP (dedup)")
                    } else {
                        sentNotificationIds.insert(messageId)
                        let notificationMessage = await messageWithResolvedAuthor(lastMessage)
                        await MainActor.run {
                            self.sendNotification(for: notificationMessage, in: space)
                        }
                        
                        if let index = self.spaces.firstIndex(where: { $0.id == space.id }) {
                            self.spaces[index].unreadCount += 1
                            self.updateDockBadge()
                            print("🟢 [Check] \(space.name): NOTIFICATION sent, unread=\(self.spaces[index].unreadCount)")
                        }
                    }
                }
            } catch {
                print("🟢 [Check] \(space.name): ERROR \(error.localizedDescription)")
            }
        }
        print("🟢 [Check] DONE")
    }

    private func messageWithResolvedAuthor(_ message: Message) async -> Message {
        guard let senderId = message.senderId, !message.isFromMe else {
            return message
        }
        
        var resolvedMessage = message
        resolvedMessage.authorName = await resolvedAuthorName(for: senderId, fallback: message.authorName)
        return resolvedMessage
    }

    private func resolvedAuthorName(for senderId: String, fallback: String) async -> String {
        if let cached = userNameCache[senderId], isUsablePersonName(cached) {
            return cached
        }
        
        let resolved = await fetchUserRealName(userId: senderId)
        if isUsablePersonName(resolved) {
            userNameCache[senderId] = resolved
            saveCache()
            return resolved
        }
        
        return fallback
    }
    
    func startBackgroundCheck() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            print("⏰ [Timer tick] spaces=\(self.spaces.count), service=\(self.chatService != nil ? "OK" : "nil")")
            Task { await self.checkAllSpacesForNewMessages() }
        }
        print("⏰ startBackgroundCheck: таймер запущен (60с)")
    }

    func stopBackgroundCheck() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = nil
    }

    private func updateDockBadge() {
        let total = spaces.reduce(0) { $0 + $1.unreadCount }
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : ""
    }
    
    private func refreshDirectChatMappingsAndNames() async {
        guard chatService != nil else { return }
        guard !currentUserId.isEmpty else {
            print("⚠️ currentUserId не загружен, пропускаем")
            return
        }
        
        print("🔄 refreshDirectChatMappingsAndNames: начат, currentUserId = \(currentUserId)")
        
        for space in spaces where space.type == .direct {
            await refreshDirectChatMappingAndName(for: space)
        }
        objectWillChange.send()
    }

    private func refreshDirectChatMappingAndName(for space: ChatSpace) async {
        guard let service = chatService else { return }
        guard !currentUserId.isEmpty else { return }
        
        do {
            let members = try await service.fetchSpaceMembers(spaceId: space.id)
            print("📋 Участники чата \(space.id): \(members)")
            
            let otherUserId = members.first { $0 != currentUserId && $0.hasPrefix("users/") }
            guard let userId = otherUserId else {
                print("⚠️ Не найден собеседник для чата \(space.id), участники: \(members)")
                return
            }
            
            if directChatUserMapping[space.id] != userId {
                directChatUserMapping[space.id] = userId
                saveMapping()
            }
            
            let name = await getDirectChatDisplayName(userId: userId)
            if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                spaces[index].name = name
                print("✅ Обновлено имя чата: \(name)")
            }
        } catch {
            print("❌ Ошибка для \(space.id): \(error)")
        }
    }

    private func getDirectChatDisplayName(userId: String) async -> String {
        if let cached = userEmailCache[userId], isUsablePersonName(cached) {
            return cached
        }
        userEmailCache.removeValue(forKey: userId)
        
        let displayName = await fetchUserRealName(userId: userId)
        userEmailCache[userId] = displayName
        return displayName
    }
    
    func sendWelcomeNotification() {
        let testMessage = Message(
            text: "Бобро поржаловать!",
            authorName: "Google Chat",
            isFromMe: false,
            timestamp: Date(),
            senderId: nil
        )
        let testSpace = ChatSpace(
            id: "welcome",
            name: "Приветствие",
            type: .direct,
            lastMessage: nil
        )
        sendNotification(for: testMessage, in: testSpace)
    }
}
