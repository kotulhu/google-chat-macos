import Foundation

class GoogleChatService {
    private var accessToken: String
    private let baseURL = "https://chat.googleapis.com/v1/"
    private weak var authManager: GoogleAuthManager?
    private var currentUserId: String?
    private var currentUserEmail: String?
    private var currentUserName: String?
    
    init(accessToken: String, authManager: GoogleAuthManager? = nil, currentUserEmail: String? = nil, currentUserName: String? = nil) {
        self.accessToken = accessToken
        self.authManager = authManager
        self.currentUserEmail = currentUserEmail
        self.currentUserName = currentUserName
    }
    
    var currentAccessToken: String {
        accessToken
    }

    private func authorizedData(for request: URLRequest, retryOnUnauthorized: Bool = true) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if retryOnUnauthorized,
           let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 401 {
            print("🔄 401 Unauthorized, пробуем обновить токен...")
            let refreshed = await authManager?.refreshAccessToken() ?? false
            guard refreshed, let newToken = authManager?.accessToken else {
                throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Token expired and refresh failed"])
            }
            self.accessToken = newToken
            return try await authorizedData(for: request, retryOnUnauthorized: false)
        }
        
        return (data, response)
    }
    
    func fetchSpaces() async throws -> [ChatSpace] {
        let url = URL(string: baseURL + "spaces")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct SpacesResponse: Decodable {
            let spaces: [SpaceItem]
        }
        struct SpaceItem: Decodable {
            let name: String
            let displayName: String?
            let spaceType: String
        }
        
        let response = try JSONDecoder().decode(SpacesResponse.self, from: data)
        
        return response.spaces.map { space in
            let type: ChatSpace.SpaceType
            switch space.spaceType {
            case "DM", "DIRECT_MESSAGE": type = .direct
            case "GROUP_CHAT": type = .group
            default: type = .channel
            }
            return ChatSpace(
                id: space.name,
                name: space.displayName ?? "Без названия",
                type: type,
                lastMessage: nil
            )
        }
    }
    
    func createDirectChat(with userId: String) async throws -> ChatSpace {
        let body: [String: Any] = [
            "spaceType": "DM",
            "singleUser": ["name": userId]
        ]
        return try await createSpaceRequest(body: body)
    }
    
    func createSpace(name: String, type: ChatSpace.SpaceType) async throws -> ChatSpace {
        let apiType: String
        switch type {
        case .channel:
            apiType = "SPACE"
        case .group:
            apiType = "GROUP_CHAT"
        case .direct:
            apiType = "DM"
        }
        
        let body: [String: Any] = [
            "displayName": name,
            "spaceType": apiType
        ]
        return try await createSpaceRequest(body: body)
    }
    
    private func createSpaceRequest(body: [String: Any]) async throws -> ChatSpace {
        let url = URL(string: baseURL + "spaces")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, domain: "GoogleChatCreateSpace")
        
        struct SpaceResponse: Decodable {
            let name: String
            let displayName: String?
            let spaceType: String?
        }
        let created = try JSONDecoder().decode(SpaceResponse.self, from: data)
        let type: ChatSpace.SpaceType
        switch created.spaceType {
        case "DM", "DIRECT_MESSAGE":
            type = .direct
        case "GROUP_CHAT":
            type = .group
        default:
            type = .channel
        }
        return ChatSpace(id: created.name, name: created.displayName ?? "Без названия", type: type, lastMessage: nil)
    }
    
    func fetchMessages(spaceId: String, pageSize: Int = 100) async throws -> [Message] {
        var components = URLComponents(string: "\(baseURL)\(spaceId)/messages")
        components?.queryItems = [
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "orderBy", value: "createTime desc")
        ]
        
        guard let url = components?.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, _) = try await authorizedData(for: request)
        
        struct MessagesResponse: Decodable {
            let messages: [MessageItem]?
        }
        
        struct MessageItem: Decodable {
            let name: String
            let text: String?
            let sender: Sender?
            let createTime: String?
            let attachment: [AttachmentItem]?
        }

        struct AttachmentItem: Decodable {
            let name: String
            let contentName: String?
            let contentType: String?
            let attachmentDataRef: AttachmentDataRef?
            let thumbnailUri: String?
            let downloadUri: String?
        }

        struct AttachmentDataRef: Decodable {
            let resourceName: String?
            let attachmentUploadToken: String?
        }
        
        struct Sender: Decodable {
            let name: String
            let displayName: String?
        }
        
        let decodedResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let messages = decodedResponse.messages?.compactMap { msg -> Message? in
            let text = msg.text ?? ""
            let senderId = msg.sender?.name
            let isFromMe = isCurrentUser(senderId) || isCurrentClientDisplayName(msg.sender?.displayName)
            
            let senderName: String
            if isFromMe {
                senderName = displayNameForCurrentUser
            } else if let displayName = msg.sender?.displayName, isUsablePersonName(displayName) {
                senderName = displayName
            } else {
                let rawId = senderId?.replacingOccurrences(of: "users/", with: "") ?? "unknown"
                senderName = "User \(rawId.prefix(8))"
            }
            
            let timestamp = msg.createTime.flatMap { formatter.date(from: $0) } ?? Date()
            
            let attachments: [Attachment] = msg.attachment?.compactMap { attach -> Attachment? in
                let contentName = attach.contentName ?? attach.name.components(separatedBy: "/").last ?? "attachment"
                let contentType = attach.contentType ?? "application/octet-stream"
                let attachmentToken = attach.attachmentDataRef?.attachmentUploadToken
                    ?? attachmentToken(from: attach.downloadUri)
                    ?? attachmentToken(from: attach.thumbnailUri)
                return Attachment(
                    name: contentName,
                    url: attach.downloadUri.flatMap { URL(string: $0) },
                    mimeType: contentType,
                    size: 0,
                    thumbnailURL: attach.thumbnailUri.flatMap { URL(string: $0) },
                    resourceName: attach.attachmentDataRef?.resourceName ?? attach.name,
                    uploadToken: attachmentToken
                )
            } ?? []
            
            guard !text.isEmpty || !attachments.isEmpty else { return nil }
      
            return Message(
                id: msg.name,
                text: text,
                authorName: senderName,
                isFromMe: isFromMe,
                timestamp: timestamp,
                attachments: attachments,
                senderId: isFromMe ? nil : senderId
            )
        } ?? []
        
        return messages
    }

    private var displayNameForCurrentUser: String {
        let localDisplayName = ConfigManager.shared.localDisplayName
        if isUsablePersonName(localDisplayName) {
            return localDisplayName
        }
        if let currentUserName, isUsablePersonName(currentUserName) {
            return currentUserName
        }
        if let currentUserEmail, !currentUserEmail.isEmpty {
            return currentUserEmail
        }
        if let currentUserId, !currentUserId.isEmpty {
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

    private func isCurrentClientDisplayName(_ name: String?) -> Bool {
        name?.trimmingCharacters(in: .whitespacesAndNewlines) == "Native Mac Client"
    }

    private func isCurrentUser(_ senderId: String?) -> Bool {
        guard let senderId = normalizedUserId(senderId) else { return false }
        if senderId.hasSuffix("users/me") { return true }
        guard let currentUserId, !currentUserId.isEmpty else { return false }
        return senderId == currentUserId
    }

    private func normalizedUserId(_ userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return userId.replacingOccurrences(of: "people/", with: "users/")
    }

    private func attachmentToken(from uri: String?) -> String? {
        guard let uri, let components = URLComponents(string: uri) else {
            return nil
        }
        return components.queryItems?.first { $0.name == "attachment_token" }?.value
    }
    
    func sendMessage(spaceId: String, text: String) async throws {
        let url = URL(string: "\(baseURL)\(spaceId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: request)
        print("📤 Сообщение отправлено")
    }
    
    func fetchUserName(userId: String) async throws -> String {
        print("📡 Запрашиваем имя для userId: \(userId)")
        let url = URL(string: "https://people.googleapis.com/v1/\(userId)?personFields=names")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 HTTP статус: \(httpResponse.statusCode)")
        }
        
        let rawResponse = String(data: data, encoding: .utf8) ?? "нет данных"
        print("📡 Сырой ответ People API: \(rawResponse)")
        
        struct ProfileResponse: Decodable {
            let names: [Name]?
            struct Name: Decodable {
                let displayName: String?
            }
        }
        
        do {
            let response = try JSONDecoder().decode(ProfileResponse.self, from: data)
            let displayName = response.names?.first?.displayName ?? "Пользователь"
            print("✅ Имя получено: \(displayName)")
            return displayName
        } catch {
            print("❌ Ошибка декодирования: \(error)")
            return "Пользователь"
        }
    }
    
    func uploadFile(fileURL: URL, to spaceId: String) async throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let mimeType = guessMimeType(from: fileName)
        
        var uploadComponents = URLComponents(string: "https://chat.googleapis.com/upload/v1/\(spaceId)/attachments:upload")!
        uploadComponents.queryItems = [
            URLQueryItem(name: "uploadType", value: "media"),
            URLQueryItem(name: "filename", value: fileName)
        ]
        guard let uploadURL = uploadComponents.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GoogleChatUpload",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Attachment upload failed: \(body)"]
            )
        }
        
        struct UploadResponse: Decodable {
            let attachmentDataRef: AttachmentDataRef?
            struct AttachmentDataRef: Decodable {
                let attachmentUploadToken: String?
            }
        }
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        guard let uploadToken = uploadResponse.attachmentDataRef?.attachmentUploadToken, !uploadToken.isEmpty else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GoogleChatUpload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Attachment upload response has no attachmentUploadToken: \(body)"]
            )
        }
        return uploadToken
    }

    private func guessMimeType(from fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
    
    func sendMessageWithAttachments(spaceId: String, text: String, attachmentUploadTokens: [String]) async throws {
        let url = URL(string: "\(baseURL)\(spaceId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "attachment": attachmentUploadTokens.map {
                ["attachmentDataRef": ["attachmentUploadToken": $0]]
            }
        ]
        if !text.isEmpty {
            body["text"] = text
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GoogleChatSend",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Message with attachment failed: \(body)"]
            )
        }
    }

    func fetchReactions(messageId: String) async throws -> [MessageReaction] {
        var allReactions: [ReactionItem] = []
        var pageToken: String?
        
        repeat {
            var components = URLComponents(string: "\(baseURL)\(messageId)/reactions")
            var queryItems = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken, !pageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else { throw URLError(.badURL) }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await authorizedData(for: request)
            try validateHTTPResponse(response, data: data, domain: "GoogleChatReactionsList")
            
            let decoded = try JSONDecoder().decode(ReactionsListResponse.self, from: data)
            allReactions.append(contentsOf: decoded.reactions ?? [])
            pageToken = decoded.nextPageToken
        } while pageToken?.isEmpty == false
        
        return aggregateReactions(allReactions)
    }

    func addReaction(messageId: String, emoji: String) async throws -> MessageReaction {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else { throw URLError(.badURL) }
        guard let url = URL(string: "\(baseURL)\(messageId)/reactions") else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["emoji": ["unicode": trimmedEmoji]])
        
        let (data, response) = try await authorizedData(for: request)
        try validateHTTPResponse(response, data: data, domain: "GoogleChatReactionsCreate")
        let reaction = try JSONDecoder().decode(ReactionItem.self, from: data)
        return aggregateReactions([reaction]).first ?? MessageReaction(
            emoji: trimmedEmoji,
            userIds: [],
            reactionNamesByUserId: [:],
            isMine: true,
            myReactionName: nil
        )
    }

    func removeReaction(reactionId: String) async throws {
        guard let url = URL(string: "\(baseURL)\(reactionId)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (data, response) = try await authorizedData(for: request)
        try validateHTTPResponse(response, data: data, domain: "GoogleChatReactionsDelete")
    }

    private struct ReactionsListResponse: Decodable {
        let reactions: [ReactionItem]?
        let nextPageToken: String?
    }

    private struct ReactionItem: Decodable {
        let name: String
        let user: ReactionUser?
        let emoji: ReactionEmoji?
    }

    private struct ReactionUser: Decodable {
        let name: String?
    }

    private struct ReactionEmoji: Decodable {
        let unicode: String?
    }

    private func aggregateReactions(_ reactions: [ReactionItem]) -> [MessageReaction] {
        var grouped: [String: [ReactionItem]] = [:]
        for reaction in reactions {
            guard let emoji = reaction.emoji?.unicode, !emoji.isEmpty else { continue }
            grouped[emoji, default: []].append(reaction)
        }
        
        return grouped.map { emoji, reactions in
            var userIds: [String] = []
            var reactionNamesByUserId: [String: String] = [:]
            var isMine = false
            var myReactionName: String?
            
            for reaction in reactions {
                guard let userId = normalizedUserId(reaction.user?.name), !userId.isEmpty else { continue }
                userIds.append(userId)
                reactionNamesByUserId[userId] = reaction.name
                if isCurrentUser(userId) {
                    isMine = true
                    myReactionName = reaction.name
                }
            }
            
            return MessageReaction(
                emoji: emoji,
                userIds: Array(Set(userIds)).sorted(),
                reactionNamesByUserId: reactionNamesByUserId,
                isMine: isMine,
                myReactionName: myReactionName
            )
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.emoji < rhs.emoji
            }
            return lhs.count > rhs.count
        }
    }
    
    func fetchUserNameViaChatAPI(userId: String) async throws -> String {
        let url = URL(string: "https://chat.googleapis.com/v1/\(userId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct UserResponse: Decodable {
            let name: String
            let displayName: String?
        }
        
        do {
            let response = try JSONDecoder().decode(UserResponse.self, from: data)
            return response.displayName ?? "Пользователь"
        } catch {
            print("❌ Chat API не вернул имя: \(error)")
            return "Пользователь"
        }
    }
    
    func downloadAttachment(resourceName: String) async throws -> Data {
        let urlString = "https://chat.googleapis.com/v1/media/\(resourceName)?alt=media"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    func updateToken(_ newToken: String) {
        self.accessToken = newToken
        print("🔧 Токен в GoogleChatService обновлён")
    }

    func updateCurrentUser(id: String? = nil, email: String? = nil, name: String? = nil) {
        if let id, !id.isEmpty {
            self.currentUserId = id.replacingOccurrences(of: "people/", with: "users/")
        }
        if let email, !email.isEmpty {
            self.currentUserEmail = email
        }
        if let name, !name.isEmpty {
            self.currentUserName = name
        }
    }
    
    func fetchUserEmail(userId: String) async throws -> String {
        let cleanId = userId.replacingOccurrences(of: "users/", with: "")
        let url = URL(string: "https://people.googleapis.com/v1/people/\(cleanId)?personFields=emailAddresses")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct PeopleResponse: Decodable {
            let emailAddresses: [EmailAddress]?
            struct EmailAddress: Decodable {
                let value: String?
            }
        }
        
        let response = try JSONDecoder().decode(PeopleResponse.self, from: data)
        let email = response.emailAddresses?.first?.value ?? ""
        return email
    }
    
    func fetchSpaceMembers(spaceId: String) async throws -> [String] {
        print("📡 fetchSpaceMembers for spaceId: \(spaceId)")
        let url = URL(string: baseURL + "\(spaceId)/members")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 HTTP статус fetchSpaceMembers: \(httpResponse.statusCode)")
        }
        let raw = String(data: data, encoding: .utf8) ?? "нет данных"
        print("📡 Ответ fetchSpaceMembers: \(raw.prefix(500))")
        
        struct MembersResponse: Decodable {
            let memberships: [Membership]
        }
        struct Membership: Decodable {
            let member: Member
        }
        struct Member: Decodable {
            let name: String
        }
        
        let responses = try JSONDecoder().decode(MembersResponse.self, from: data)
        let userIds = responses.memberships.map { $0.member.name }
        print("📡 Участники: \(userIds)")
        return userIds
    }

    func fetchSpaceMemberUsers(spaceId: String) async throws -> [ChatUser] {
        print("📡 fetchSpaceMemberUsers for spaceId: \(spaceId)")
        let url = URL(string: baseURL + "\(spaceId)/members")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, domain: "GoogleChatMembers")
        
        struct MembersResponse: Decodable {
            let memberships: [Membership]?
        }
        struct Membership: Decodable {
            let member: Member?
        }
        struct Member: Decodable {
            let name: String
            let displayName: String?
            let type: String?
            let avatarUrl: String?
            let email: String?
        }
        
        let decoded = try JSONDecoder().decode(MembersResponse.self, from: data)
        return decoded.memberships?.compactMap { membership in
            guard let member = membership.member, member.name.hasPrefix("users/") else {
                return nil
            }
            return ChatUser(
                id: member.name,
                email: member.email,
                displayName: member.displayName,
                avatarURL: member.avatarUrl.flatMap(URL.init(string:))
            )
        } ?? []
    }

    func fetchCurrentUserId() async throws -> String {
        let url = URL(string: "https://people.googleapis.com/v1/people/me?personFields=metadata")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable {
            let resourceName: String
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.resourceName
    }
    
    private func validateHTTPResponse(_ response: URLResponse, data: Data, domain: String) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: domain,
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }
    }
}
