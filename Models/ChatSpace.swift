import Foundation

struct ChatSpace: Identifiable, Hashable {
    let id: String          // "spaces/xxxx"
    var name: String        // displayName
    let type: SpaceType
    let lastMessage: String?
    var unreadCount: Int = 0              // новое
    var lastReadTimestamp: Date? = nil    // новое
    
    enum SpaceType {
        case channel, direct, group
    }
}
