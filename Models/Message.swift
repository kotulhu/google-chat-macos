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

/// A snapshot of a message quoted by another message.  `messageId` is the full
/// `spaces/{space}/messages/{message}` resource name (identical to `Message.id`),
/// which doubles as the scroll anchor of the quoted row.  `authorName`/`text`
/// are a local snapshot used when the original is not loaded in the feed.
struct QuotedMessage: Equatable, Codable {
    let messageId: String
    var authorName: String?
    var text: String?
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
    var quotedMessage: QuotedMessage?
    /// Server-format timestamp (`createTime` fallback) sent to the API inside
    /// `quotedMessageMetadata.lastUpdateTime` when this message is quoted.
    let lastUpdateTime: String?
    /// `spaces/{space}/threads/{thread}`. Present on **every** message the API
    /// returns: a message that has never been replied to still gets a thread id
    /// equal to its own message id, so this alone does not mark a thread.
    var threadName: String?
    /// Client-assigned thread key. Only ever set on messages this app created;
    /// for everyone else the API reports it as output only.
    var threadKey: String?
    /// Output-only API flag, present only when `true`: the message is a reply
    /// inside a thread. Replies are hidden from the top-level conversation and
    /// shown nested under their root instead.
    var isThreadReply: Bool = false

    /// Last component of `threadName` — the id Google Chat assigns to the
    /// thread. For a standalone message it equals the id of the message itself,
    /// which is exactly the id a future reply will join.
    var threadId: String? {
        guard let name = threadName, !name.isEmpty else { return nil }
        return name.split(separator: "/").last.map(String.init)
    }

    /// True when this message is itself the root of a thread rather than a
    /// reply. Its `threadName` is then only a placeholder until something is
    /// posted into it.
    var isThreadRoot: Bool {
        !isThreadReply
    }

    /// The resource name a reply addressed to this message's thread should use.
    /// Meaningful only for messages that already live inside a thread.
    var existingThreadName: String? {
        guard isThreadReply else { return nil }
        return threadName
    }
    
    init(
        id: String = UUID().uuidString,
        text: String,
        authorName: String,
        isFromMe: Bool,
        timestamp: Date,
        attachments: [Attachment] = [],
        senderId: String?,
        reactions: [MessageReaction] = [],
        quotedMessage: QuotedMessage? = nil,
        lastUpdateTime: String? = nil,
        threadName: String? = nil,
        threadKey: String? = nil,
        isThreadReply: Bool = false
    ) {
        self.id = id
        self.text = text
        self.authorName = authorName
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.attachments = attachments
        self.senderId = senderId
        self.reactions = reactions
        self.quotedMessage = quotedMessage
        self.lastUpdateTime = lastUpdateTime
        self.threadName = threadName
        self.threadKey = threadKey
        self.isThreadReply = isThreadReply
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
        quotedMessage = try container.decodeIfPresent(QuotedMessage.self, forKey: .quotedMessage)
        lastUpdateTime = try container.decodeIfPresent(String.self, forKey: .lastUpdateTime)
        threadName = try container.decodeIfPresent(String.self, forKey: .threadName)
        threadKey = try container.decodeIfPresent(String.self, forKey: .threadKey)
        isThreadReply = try container.decodeIfPresent(Bool.self, forKey: .isThreadReply) ?? false
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.authorName == rhs.authorName &&
        lhs.isFromMe == rhs.isFromMe &&
        lhs.timestamp == rhs.timestamp &&
        lhs.attachments == rhs.attachments &&
        lhs.reactions == rhs.reactions &&
        lhs.quotedMessage == rhs.quotedMessage &&
        lhs.lastUpdateTime == rhs.lastUpdateTime &&
        lhs.threadName == rhs.threadName &&
        lhs.threadKey == rhs.threadKey &&
        lhs.isThreadReply == rhs.isThreadReply
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
        case quotedMessage
        case lastUpdateTime
        case threadName
        case threadKey
        case isThreadReply
    }
}
