import Foundation

struct Attachment: Identifiable, Equatable, Codable {
    var id: String { resourceName ?? uploadToken ?? url?.absoluteString ?? name }
    let name: String
    let url: URL?
    let mimeType: String
    let size: Int64
    let thumbnailURL: URL?
    let resourceName: String?  
    let uploadToken: String?
    
    var isImage: Bool {
        if mimeType.hasPrefix("image/") { return true }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"]
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case url
        case mimeType
        case size
        case thumbnailURL
        case resourceName
        case uploadToken
    }
}

struct MessageReaction: Identifiable, Equatable, Codable {
    var id: String { emoji }
    let emoji: String
    var userIds: [String]
    var reactionNamesByUserId: [String: String]
    var isMine: Bool
    var myReactionName: String?
    
    var count: Int {
        userIds.count
    }
    
}

struct Message: Identifiable, Equatable, Codable {
    let id: String
    let text: String
    var authorName: String
    let isFromMe: Bool
    let timestamp: Date
    var attachments: [Attachment] = []
    let senderId: String?
    var reactions: [MessageReaction] = []
    
    init(
        id: String = UUID().uuidString,
        text: String,
        authorName: String,
        isFromMe: Bool,
        timestamp: Date,
        attachments: [Attachment] = [],
        senderId: String?,
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.text = text
        self.authorName = authorName
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.attachments = attachments
        self.senderId = senderId
        self.reactions = reactions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        authorName = try container.decode(String.self, forKey: .authorName)
        isFromMe = try container.decode(Bool.self, forKey: .isFromMe)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
        reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.authorName == rhs.authorName &&
        lhs.isFromMe == rhs.isFromMe &&
        lhs.timestamp == rhs.timestamp &&
        lhs.attachments == rhs.attachments &&
        lhs.reactions == rhs.reactions
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case authorName
        case isFromMe
        case timestamp
        case attachments
        case senderId
        case reactions
    }
}
