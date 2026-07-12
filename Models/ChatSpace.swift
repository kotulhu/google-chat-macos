import Foundation

struct ChatSpace: Identifiable, Hashable {
    let id: String
    var name: String
    let type: SpaceType
    let lastMessage: String?
    var unreadCount: Int = 0
    var lastReadTimestamp: Date? = nil
    
    enum SpaceType {
        case channel, direct, group
    }
}
