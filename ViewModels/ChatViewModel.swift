import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ChatViewModel: NSObject,ObservableObject {
    /// Spaces shown in the sidebar, sorted by recent activity.
    @Published var spaces: [ChatSpace] = []
    /// Messages of the currently selected space.
    @Published var messages: [Message] = []
    /// The currently open chat.
    @Published var selectedSpace: ChatSpace?
    @Published var isLoading = false
    /// Latest user-facing error message (localized by `L`).
    @Published var errorMessage: String?
    /// Members of `selectedSpace`.
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
    private var knownPeopleCache: [String: ChatUser] = [:]
    private var peopleSearchPrepared = false
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
        await self?.loadReactions(for: messageId, force: true)
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

    /// Applies a changed local display name to the service and to any messages
    /// authored by the current user, then notifies observers.
    @objc private func localDisplayNameDidChange() {
        currentUserName = ConfigManager.shared.localDisplayName
        chatService?.updateCurrentUser(name: currentUserDisplayName)
        
        for index in messages.indices where messages[index].isFromMe {
            messages[index].authorName = currentUserDisplayName
        }
        objectWillChange.send()
    }
    /// Resolves the current user's People API ID via the service, normalizes it
    /// to the `users/` form and stores it for ownership checks.
    func setCurrentUserId() async {
        do {
            let peopleId = try await chatService?.fetchCurrentUserId() ?? ""
            currentUserId = peopleId.replacingOccurrences(of: "people/", with: "users/")
            chatService?.updateCurrentUser(id: currentUserId)
            print("✅ Current user ID: \(currentUserId)")
        } catch {
            print("❌ Failed to get current user ID: \(error)")
        }
    }
    
    /// Restores the persisted direct-chat → user mapping from UserDefaults.
    private func loadMapping() {
        directChatUserMapping = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        print("DEBUG: mapping loaded from UserDefaults: \(directChatUserMapping)")
    }

    /// Persists the direct-chat → user mapping only when it actually changed.
    private func saveMapping() {
        let currentMapping = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        if currentMapping != directChatUserMapping {
            defaults.set(directChatUserMapping, forKey: mappingKey)
            print("DEBUG: mapping saved")
        }
    }
    
    /// Restores the persisted user-name resolution cache.
    private func loadCache() {
        userNameCache = cacheDefaults.dictionary(forKey: userNameCacheKey) as? [String: String] ?? [:]
        print("DEBUG: user name cache loaded: \(userNameCache)")
    }

    /// Persists the user-name resolution cache to UserDefaults.
    private func saveCache() {
        cacheDefaults.set(userNameCache, forKey: userNameCacheKey)
    }

    /// Fetches and caches the current user ID, then refreshes direct-chat
    /// names now that the user identity is known.
    func fetchCurrentUserId() async {
        guard let service = chatService else { return }
        do {
            currentUserId = try await service.fetchCurrentUserId()
            currentUserId = currentUserId.replacingOccurrences(of: "people/", with: "users/")
            chatService?.updateCurrentUser(id: currentUserId)
            print("✅ Current user ID: \(currentUserId)")
        } catch {
            print("❌ Failed to get ID: \(error)")
        }
        await refreshDirectChatMappingsAndNames()
    }
    
    /// Schedules periodic access-token refresh (every 50 minutes) and pushes
    /// each refreshed token into the service.
    func startTokenRefreshTimer(authManager: GoogleAuthManager) {
        tokenRefreshTimer?.invalidate()
        print("⏰ Starting token refresh timer (every 50 minutes)")
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 50 * 60, repeats: true) { _ in
            print("🔄 Timer fired, refreshing token...")
            Task {
                let success = await authManager.refreshAccessToken()
                if success {
                    await MainActor.run {
                        let token = authManager.accessToken
                        print("✅ Token refreshed, new token: \(token.prefix(50))...")
                        self.accessToken = token
                        self.chatService?.updateToken(token)
                    }
                } else {
                    print("❌ Failed to refresh token")
                }
            }
        }
    }

    /// Cancels the token refresh timer.
    func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    /// Starts the 5-second message poll for the given space (only while the
    /// space stays selected) and resumes reaction viewport tracking.
    func startPolling(for space: ChatSpace) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let currentSpace = self.selectedSpace, currentSpace.id == space.id else { return }
            Task {
                PerfBeacon.mark("Lenta", phase: "pollTick")
                await self.loadMessages(for: space)
            }
        }
        reactionViewportController.start()
        print("🔄 [Poll] startPolling for: \(space.name), backgroundCheckTimer=\(backgroundCheckTimer != nil ? "running" : "NOT running")")
    }

    /// Stops the current space poll and reaction viewport tracking.
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        reactionViewportController.stop()
        print("🛑 Polling stopped")
    }
    
    /// Binds the view model to an access token and auth manager, builds the
    /// chat service, resets transient caches and starts background refresh.
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
        print("🔧 ChatViewModel configured")
        
        sentNotificationIds.removeAll()
        print("🧹 sentNotificationIds cleared")
        Task {
            await setCurrentUserId()
        }
        
        startBackgroundRefresh()
    }
    
    /// Loads all spaces from the API, sorts them, wires background checks,
    /// resolves direct-chat names, refreshes unread counts and selects the
    /// first space so its messages load immediately.
    func loadSpaces() async {
        print("📡 loadSpaces() started")
        guard let service = chatService else {
            print("❌ chatService = nil (no token passed)")
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedSpaces = try await service.fetchSpaces()
            
            print("✅ Fetched \(fetchedSpaces.count) chats")
            self.spaces = fetchedSpaces
            sortSpaces()
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
            errorMessage = L.str("err.load.chats", error.localizedDescription)
            print("❌ \(errorMessage!)")
        }
    }
    
    /// Fetches the newest message of every space in parallel to update the
    /// sidebar timestamps, unread badges and the dock badge.
    func refreshUnreadCounts() async {
        PerfBeacon.mark("Bg", phase: "refreshUnreadCounts START", detail: "spaces=\(spaces.count)")
        guard let service = chatService else { return }
        PerfBeacon.start("Bg", phase: "refreshUnreadCounts")
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
                    if let lastMessage = lastMessage {
                        spaces[index].lastMessageTimestamp = lastMessage.timestamp
                    }
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
        PerfBeacon.end("Bg", phase: "refreshUnreadCounts", detail: "spaces=\(spaces.count)")
        updateDockBadge()
    }
    
    /// Starts the 30-second unread-count background refresh.
    func startBackgroundRefresh() {
        backgroundTimer?.invalidate()
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshUnreadCounts() }
        }
    }

    /// Stops the unread-count background refresh.
    func stopBackgroundRefresh() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }
    
    /// Returns a cached user name synchronously; falls back to a short-ID label.
    func getUserNameSync(userId: String) -> String {
        if let cached = userNameCache[userId], isUsablePersonName(cached) {
            return cached
        }
        userNameCache.removeValue(forKey: userId)
        let shortId = userId.replacingOccurrences(of: "users/", with: "").suffix(6)
        return "User \(shortId)"
    }
    
    /// Loads the messages of a space (cache first, then network), assigns
    /// resolved author names and reactions, updates the space timestamp, and
    /// re-sorts the list when a newer message arrived.
    func loadMessages(for space: ChatSpace) async {
        PerfBeacon.start("Lenta", phase: "loadMessages")
        guard let service = chatService else { return }
        isLoading = true
        defer { isLoading = false }
        
        PerfBeacon.start("Lenta", phase: "cacheRead")
        let cachedMessages = MessageCache.shared.get(spaceId: space.id)
        PerfBeacon.end("Lenta", phase: "cacheRead", detail: "count=\(cachedMessages?.count ?? 0)")
        if let cachedMessages, !cachedMessages.isEmpty {
            for message in cachedMessages where !message.reactions.isEmpty {
                reactionCache[message.id] = message.reactions
            }
            self.messages = normalizeMessagesForDisplay(cachedMessages)
        }
        
        do {
            PerfBeacon.start("Lenta", phase: "fetch")
            let fetchedMessages = try await service.fetchMessages(spaceId: space.id)
            PerfBeacon.end("Lenta", phase: "fetch", detail: "count=\(fetchedMessages.count)")
            accessToken = service.currentAccessToken
            
            if space.type == .direct {
                await refreshDirectChatMappingAndName(for: space)
            }
            
            PerfBeacon.start("Lenta", phase: "buildNames")
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
            PerfBeacon.end("Lenta", phase: "buildNames", detail: "count=\(messagesWithNames.count)")
            let changed = self.messages != messagesWithNames
            PerfBeacon.start("Lenta", phase: "assign")
            if changed {
                self.messages = messagesWithNames
            }
            PerfBeacon.end("Lenta", phase: "assign", detail: "changed=\(changed)")
            PerfBeacon.start("Lenta", phase: "cacheWrite")
            MessageCache.shared.set(messagesWithNames, forSpaceId: space.id)
            PerfBeacon.end("Lenta", phase: "cacheWrite", detail: "count=\(messagesWithNames.count)")
            
            if let latestMsg = messagesWithNames.last,
               let idx = spaces.firstIndex(where: { $0.id == space.id }) {
                let old = spaces[idx].lastMessageTimestamp
                let hasNewer = latestMsg.timestamp > (old ?? .distantPast)
                if old == nil || hasNewer {
                    spaces[idx].lastMessageTimestamp = latestMsg.timestamp
                    if hasNewer {
                        sortSpaces()
                    }
                }
            }
            
        } catch {
            if cachedMessages?.isEmpty != false {
                errorMessage = L.str("err.load.messages", error.localizedDescription)
                print("❌ \(errorMessage!)")
            } else {
                print("⚠️ Could not refresh messages from network, showing cache: \(error)")
            }
        }
        PerfBeacon.end("Lenta", phase: "loadMessages", detail: space.name)
    }

    /// Rewrites messages authored by the legacy "Native Mac Client" marker so
    /// they read as coming from the current user.
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
    
    /// Sends a plain text message to the selected space and reloads messages.
    @discardableResult
    func sendMessage(_ text: String) async -> Bool {
        guard let service = chatService, let space = selectedSpace else { return false }
        do {
            try await service.sendMessage(spaceId: space.id, text: text)
            await loadMessages(for: space)
            return true
        } catch {
            errorMessage = L.str("err.send", error.localizedDescription)
            print("❌ \(errorMessage!)")
            return false
        }
    }
    
    /// Resets all caches and stops every background task (used on sign-out).
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
        print("🧹 Data cleared")
    }
    

    /// Returns the cached display name for a user, or a short-ID fallback while
    /// the real name is being resolved asynchronously in the background.
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
                    PerfBeacon.measure("Lenta", phase: "nameResolutionUpdate", minMs: 1, detail: "messages=\(self.messages.count), sender=\(userId)") {
                        for i in self.messages.indices {
                            if self.messages[i].senderId == userId {
                                self.messages[i].authorName = realName
                            }
                        }
                        self.objectWillChange.send()
                    }
                }
            }
        }
        
        return fallback
    }

    /// Best-effort display name for the current user: local override, Google
    /// account name, e-mail, user ID, and finally the legacy marker.
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

    /// Returns whether a name is meaningful enough to display (not empty, not a
    /// known placeholder like "Native Mac Client" or the localized unknown-user
    /// fallback).
    private func isUsablePersonName(_ name: String?) -> Bool {
        guard let name else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != "Native Mac Client" && trimmed != L.str("user.unknown")
    }
    
    /// Resolves a user's display name, trying the Chat API first and the People
    /// API e-mail as a fallback, ending with a short-ID label.
    private func fetchUserRealName(userId: String) async -> String {
        do {
            let name = try await chatService?.fetchUserNameViaChatAPI(userId: userId) ?? ""
            if isUsablePersonName(name) {
                print("✅ Name from Chat API: \(name) for \(userId)")
                return name
            }
        } catch {
            print("⚠️ Chat API returned no name for \(userId): \(error)")
        }

        do {
            let email = try await chatService?.fetchUserEmail(userId: userId) ?? ""
            if !email.isEmpty {
                return email
            }
        } catch {
            print("⚠️ People API returned no email for \(userId): \(error)")
        }

        let shortId = userId.replacingOccurrences(of: "users/", with: "").suffix(6)
        return "User \(shortId)"
    }
    
    /// Uploads a file attachment to the service for the given space.
    func uploadFile(fileURL: URL, to spaceId: String) async throws -> String {
        guard let service = chatService else { throw NSError(domain: "Chat", code: 0, userInfo: [NSLocalizedDescriptionKey: "Service not configured"]) }
        return try await service.uploadFile(fileURL: fileURL, to: spaceId)
    }

    /// Creates a new space, inserts it at the top of the list and opens it.
    func createSpace(name: String, type: ChatSpace.SpaceType) async -> Bool {
        guard let service = chatService else { return false }
        do {
            let created = try await service.createSpace(name: name, type: type)
            spaces.insert(created, at: 0)
            selectedSpace = created
            await loadMessages(for: created)
            return true
        } catch {
            errorMessage = L.str("err.create.chat", error.localizedDescription)
            print("❌ \(errorMessage!)")
            return false
        }
    }

    /// Opens (or creates) a direct chat with a user, selecting it for display.
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
            errorMessage = L.str("err.open.chat", error.localizedDescription)
            print("❌ \(errorMessage!)")
        }
    }

    /// Loads the members of a space (cached after the first call) and populates
    /// the shared known-people cache for search.
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
            for member in enrichedMembers {
                rememberKnownPerson(member)
            }
            if selectedSpace?.id == spaceId {
                currentSpaceMembers = enrichedMembers
            }
        } catch {
            print("❌ Failed to load members: \(error)")
            if selectedSpace?.id == spaceId {
                currentSpaceMembers = []
            }
        }
    }

    /// Indexes a user into the local searchable cache (skipping the current user).
    private func rememberKnownPerson(_ user: ChatUser) {
        guard !user.id.isEmpty, user.id != currentUserId else { return }
        knownPeopleCache[user.id] = user
    }

    /// One-time warm-up of the search index: loads the full contact list plus the
    /// members of every space (in parallel), enriching each user with e-mails.
    private func preparePeopleSearch() async {
        guard !peopleSearchPrepared else { return }
        peopleSearchPrepared = true
        
        if let service = chatService,
           let contacts = try? await service.fetchAllContacts() {
            for contact in contacts {
                rememberKnownPerson(contact)
            }
        }
        
        guard let service = chatService else { return }
        let spaceIds = spaces.map { $0.id }
        let loaded: [String: [ChatUser]] = await withTaskGroup(of: (String, [ChatUser])?.self) { group in
            for spaceId in spaceIds where memberCache[spaceId] == nil {
                group.addTask {
                    guard let members = try? await service.fetchSpaceMemberUsers(spaceId: spaceId) else {
                        return nil
                    }
                    return (spaceId, members)
                }
            }
            var result: [String: [ChatUser]] = [:]
            for await item in group {
                if let item {
                    result[item.0] = item.1
                }
            }
            return result
        }
        
        for (spaceId, members) in loaded {
            let enriched = await enrichUsersWithEmails(members)
            memberCache[spaceId] = enriched
            for member in enriched {
                rememberKnownPerson(member)
            }
        }
    }

    /// Searches the local index of known people by e-mail, name or user ID.
    func searchUsers(query: String) async -> [ChatUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()
        
        await preparePeopleSearch()
        
        let results = knownPeopleCache.values.filter { user in
            guard user.id != currentUserId else { return false }
            let email = (user.email ?? "").lowercased()
            let name = (user.displayName ?? "").lowercased()
            let id = user.id.lowercased()
            return email.contains(q) || name.contains(q) || id.contains(q)
        }
        
        return results.sorted {
            let lhs = $0.email ?? $0.displayTitle
            let rhs = $1.email ?? $1.displayTitle
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    /// Fills missing e-mails for a list of users using the cached values or the
    /// People API, so display and search can rely on e-mail addresses.
    private func enrichUsersWithEmails(_ users: [ChatUser]) async -> [ChatUser] {
        var result: [ChatUser] = []
        for user in users {
            if let email = user.email, !email.isEmpty {
                userEmailCache[user.id] = email
                result.append(user)
                continue
            }
            
            if let cachedEmail = userEmailCache[user.id], !cachedEmail.isEmpty {
                result.append(ChatUser(id: user.id, email: cachedEmail, displayName: user.displayName, avatarURL: user.avatarURL, membershipName: user.membershipName))
                continue
            }
            
            do {
                let email = try await chatService?.fetchUserEmail(userId: user.id) ?? ""
                if !email.isEmpty {
                    userEmailCache[user.id] = email
                    result.append(ChatUser(id: user.id, email: email, displayName: user.displayName, avatarURL: user.avatarURL, membershipName: user.membershipName))
                    continue
                }
            } catch {
                print("⚠️ Could not get email for \(user.id): \(error)")
            }
            
            result.append(user)
        }
        return result
    }

    /// The resolved API ID of the current user (`users/...`).
    var myUserId: String {
        currentUserId
    }

    /// Adds a user as a member of a space and refreshes the member list.
    func addMember(_ user: ChatUser, to spaceId: String) async {
        guard let service = chatService else { return }
        do {
            _ = try await service.createMembership(spaceId: spaceId, userId: user.id)
            memberCache.removeValue(forKey: spaceId)
            await loadMembers(for: spaceId)
        } catch {
            errorMessage = L.str("err.add.member", error.localizedDescription)
            print("❌ \(errorMessage!)")
        }
    }

    /// Removes a user from a space and updates the local member list.
    func removeMember(_ user: ChatUser, from spaceId: String) async {
        guard let service = chatService else { return }
        guard let membershipName = user.membershipName else {
            errorMessage = L.str("err.remove.member.noData")
            return
        }
        do {
            try await service.deleteMembership(membershipName: membershipName)
            memberCache.removeValue(forKey: spaceId)
            currentSpaceMembers.removeAll { $0.id == user.id }
        } catch {
            errorMessage = L.str("err.remove.member", error.localizedDescription)
            print("❌ \(errorMessage!)")
        }
    }

    /// Makes the current user leave a space and clears it from the UI.
    func leaveSpace(_ spaceId: String) async {
        guard let service = chatService else { return }
        let myMembership = currentSpaceMembers.first { $0.id == currentUserId }?.membershipName
        do {
            if let myMembership {
                try await service.deleteMembership(membershipName: myMembership)
            } else {
                try await service.deleteMembershipByUserId(spaceId: spaceId, userId: currentUserId)
            }
            spaces.removeAll { $0.id == spaceId }
            memberCache.removeValue(forKey: spaceId)
            if selectedSpace?.id == spaceId {
                selectedSpace = nil
                messages = []
                currentSpaceMembers = []
            }
        } catch {
            errorMessage = L.str("err.leave.chat", error.localizedDescription)
            print("❌ \(errorMessage!)")
        }
    }

    /// Sends a message, optionally with uploaded attachments, then reloads the
    /// space so the new message appears immediately.
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
            errorMessage = L.str("err.send", error.localizedDescription)
            print("❌ \(errorMessage!)")
            return false
        }
    }

    /// Notifies the reaction viewport controller that a message became visible
    /// (so lazy reaction loading can trigger).
    func markReactionViewportVisible(id: String) {
        reactionViewportController.markVisible(id: id)
    }

    /// Notifies the reaction viewport controller that a message left the viewport.
    func markReactionViewportHidden(id: String) {
        reactionViewportController.markHidden(id: id)
    }

    /// Loads reactions for a message (unless cached, or unless `force` is set),
    /// then applies them to the display list.
    func loadReactions(for messageId: String, force: Bool = false) async {
        if !force, let cached = reactionCache[messageId] {
            applyReactions(cached, to: messageId)
            return
        }
        guard !loadingReactionMessageIds.contains(messageId), let service = chatService else {
            return
        }
        
        loadingReactionMessageIds.insert(messageId)
        defer { loadingReactionMessageIds.remove(messageId) }
        
        PerfBeacon.start("React", phase: force ? "loadReactions(force)" : "loadReactions")
        do {
            let reactions = try await service.fetchReactions(messageId: messageId)
            PerfBeacon.end("React", phase: force ? "loadReactions(force)" : "loadReactions", detail: "count=\(reactions.count), message=\(messageId.suffix(12))")
            reactionCache[messageId] = reactions
            applyReactions(reactions, to: messageId)
        } catch {
            PerfBeacon.end("React", phase: force ? "loadReactions(force)" : "loadReactions", detail: "ERROR")
            guard !isCancellation(error) else {
                return
            }
            print("❌ Failed to load reactions for \(messageId): \(error)")
        }
    }

    /// Optimistically toggles the current user's reaction on a message, then
    /// reconciles with the server state, restoring the old state on failure.
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
                ReactionHistoryStore.shared.record(emoji)
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
            print("❌ Failed to toggle reaction \(emoji) for \(messageId): \(error)")
            reactionCache[messageId] = oldReactions
            applyReactions(oldReactions, to: messageId)
        }
    }

    /// Mutates the in-memory reactions of a message and notifies observers.
    private func applyReactions(_ reactions: [MessageReaction], to messageId: String) {
        reactionCache[messageId] = reactions
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            PerfBeacon.measure("React", phase: "applyReactions", minMs: 1, detail: "count=\(reactions.count)") {
                messages[index].reactions = reactions
                objectWillChange.send()
            }
        }
    }

    /// Computes the resulting reaction list after the current user toggles an
    /// emoji, keeping counts and user sets consistent.
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

    /// Whether an error represents a cancelled task or URL request.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
    
    /// Returns the ID of the message at or before the space's last-read mark.
    func lastReadMessageId(in messages: [Message]) -> String? {
        guard let space = selectedSpace else { return nil }
        let lastRead = space.lastReadTimestamp ?? Date()
        if let candidate = messages.last(where: { $0.timestamp <= lastRead }) {
            return candidate.id
        }
        return messages.last?.id
    }
    
    /// Chooses where the message list should initially scroll: the first unread
    /// message, or the newest one if everything has been read.
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
    
    /// Persists the last-read timestamp for a space and updates the unread badge.
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
    
    /// Stores a space's last-read timestamp in UserDefaults.
    func saveLastReadTimestamp(for spaceId: String, date: Date) {
        defaults.set(date, forKey: lastReadKeyPrefix + spaceId)
        print("DEBUG: mapping saved: \(directChatUserMapping)")
    }

    /// Loads a space's persisted last-read timestamp.
    private func loadLastReadTimestamp(for spaceId: String) -> Date? {
        return defaults.object(forKey: lastReadKeyPrefix + spaceId) as? Date
    }
    
    /// Sends the current message and forces a final UI refresh for the scroll view.
    func sendMessageAndScroll(_ text: String) async {
        await sendMessage(text)
        await MainActor.run {
            objectWillChange.send()
        }
    }
    /// Shows a macOS notification for an incoming message in a space.
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
    
    /// Scans every non-selected space for newer incoming messages, sends a
    /// notification (deduplicated) per the latest one and bumps unread counts.
    func checkAllSpacesForNewMessages() async {
        PerfBeacon.mark("Bg", phase: "checkAllSpaces START", detail: "spaces=\(spaces.count)")
        print("🟢 [Check] START: spaces=\(spaces.count), selected=\(selectedSpace?.name ?? "nil"), dedup=\(sentNotificationIds.count)")
        guard let service = chatService else {
            print("🟢 [Check] ABORT: chatService=nil")
            return
        }
        PerfBeacon.start("Bg", phase: "checkAllSpaces")
        
        var hasNewMessage = false
        for space in spaces {
            if selectedSpace?.id == space.id { continue }
            
            do {
                let latestMessages = try await service.fetchMessages(spaceId: space.id, pageSize: 1)
                guard let lastMessage = latestMessages.first else { continue }
                
                if let idx = spaces.firstIndex(where: { $0.id == space.id }) {
                    let old = spaces[idx].lastMessageTimestamp
                    let hasNewer = lastMessage.timestamp > (old ?? .distantPast)
                    if old == nil || hasNewer {
                        spaces[idx].lastMessageTimestamp = lastMessage.timestamp
                    }
                }
                
                guard !lastMessage.isFromMe else { continue }
                
                var lastRead = loadLastReadTimestamp(for: space.id)
                if let readDate = lastRead, readDate.timeIntervalSince1970 < 1000000000 {
                    lastRead = nil
                }
                let actualLastRead: Date
                if let lr = lastRead {
                    actualLastRead = lr
                } else {
                    actualLastRead = lastMessage.timestamp
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
                        hasNewMessage = true
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
        if hasNewMessage { sortSpaces() }
        PerfBeacon.end("Bg", phase: "checkAllSpaces", detail: "spaces=\(spaces.count), hasNew=\(hasNewMessage)")
        print("🟢 [Check] DONE")
    }

    /// Resolves a message's author name before it is used in a notification.
    private func messageWithResolvedAuthor(_ message: Message) async -> Message {
        guard let senderId = message.senderId, !message.isFromMe else {
            return message
        }
        
        var resolvedMessage = message
        resolvedMessage.authorName = await resolvedAuthorName(for: senderId, fallback: message.authorName)
        return resolvedMessage
    }

    /// Best-effort name for a sender, preferring the name cache and falling back
    /// to the value already stored on the message.
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
    
    /// Starts the 60-second background check for new incoming messages.
    func startBackgroundCheck() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            print("⏰ [Timer tick] spaces=\(self.spaces.count), service=\(self.chatService != nil ? "OK" : "nil")")
            Task { await self.checkAllSpacesForNewMessages() }
        }
        print("⏰ startBackgroundCheck: timer started (60s)")
    }

    /// Stops the background new-message check.
    func stopBackgroundCheck() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = nil
    }

    /// Refreshes the dock tile badge with the total unread count across spaces.
    private func updateDockBadge() {
        let total = spaces.reduce(0) { $0 + $1.unreadCount }
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : ""
    }
    
    /// Sorts spaces by newest activity (message timestamp), with direct chats
    /// before groups/channels and names as the final tiebreaker.
    private func sortSpaces() {
        spaces = spaces.sorted { a, b in
            let aTime = a.lastMessageTimestamp ?? .distantPast
            let bTime = b.lastMessageTimestamp ?? .distantPast
            if aTime != bTime {
                return aTime > bTime
            }
            if a.type != b.type {
                if a.type == .direct { return true }
                if b.type == .direct { return false }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    
    /// Re-resolves names for every direct chat in the sidebar (needs the current
    /// user ID to know which member is the conversation partner).
    private func refreshDirectChatMappingsAndNames() async {
        guard chatService != nil else { return }
        guard !currentUserId.isEmpty else {
            print("⚠️ currentUserId not loaded, skipping")
            return
        }
        
        print("🔄 refreshDirectChatMappingsAndNames: started, currentUserId = \(currentUserId)")
        
        for space in spaces where space.type == .direct {
            await refreshDirectChatMappingAndName(for: space)
        }
        objectWillChange.send()
    }

    /// Resolves the display name of one direct chat: finds the non-current member
    /// and shows their human-readable name as the chat title.
    private func refreshDirectChatMappingAndName(for space: ChatSpace) async {
        guard let service = chatService else { return }
        guard !currentUserId.isEmpty else { return }
        
        do {
            let members = try await service.fetchSpaceMembers(spaceId: space.id)
            print("📋 Members of chat \(space.id): \(members)")
            
            let otherUserId = members.first { $0 != currentUserId && $0.hasPrefix("users/") }
            guard let userId = otherUserId else {
                print("⚠️ No interlocutor found for chat \(space.id), members: \(members)")
                return
            }
            
            if directChatUserMapping[space.id] != userId {
                directChatUserMapping[space.id] = userId
                saveMapping()
            }
            
            let name = await getDirectChatDisplayName(userId: userId)
            if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                spaces[index].name = name
                print("✅ Updated chat name: \(name)")
            }
        } catch {
            print("❌ Error for \(space.id): \(error)")
        }
    }

    /// Human-readable title for a direct chat, resolved from the partner user.
    private func getDirectChatDisplayName(userId: String) async -> String {
        if let cached = userEmailCache[userId], isUsablePersonName(cached) {
            return cached
        }
        userEmailCache.removeValue(forKey: userId)
        
        let displayName = await fetchUserRealName(userId: userId)
        userEmailCache[userId] = displayName
        return displayName
    }
    
    /// Posts a sample welcome notification, used to demonstrate the badge
    /// and notification flow right after a successful sign-in.
    func sendWelcomeNotification() {
        let testMessage = Message(
            text: L.str("welcome.message"),
            authorName: "Google Chat",
            isFromMe: false,
            timestamp: Date(),
            senderId: nil
        )
        let testSpace = ChatSpace(
            id: "welcome",
            name: L.str("welcome.space"),
            type: .direct,
            lastMessage: nil
        )
        sendNotification(for: testMessage, in: testSpace)
    }
}
