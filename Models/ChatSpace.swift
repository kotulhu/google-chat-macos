import Foundation

struct ChatSpace: Identifiable, Hashable {
    let id: String
    var name: String
    let type: SpaceType
    let lastMessage: String?
    var unreadCount: Int = 0
    var lastReadTimestamp: Date? = nil
    var lastMessageTimestamp: Date? = nil
    var isPinned: Bool = false
    /// Set to `true` when the other member's membership state is `INVITED`
    /// (DM request not yet accepted → sending messages is blocked).
    var isRequestPending: Bool = false
    
    enum SpaceType {
        case channel, direct, group
    }
}
