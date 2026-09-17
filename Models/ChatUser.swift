import Foundation

struct ChatUser: Identifiable, Hashable, Codable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarURL: URL?
    var membershipName: String?
    /// `JOINED`, `INVITED` or `NOT_A_MEMBER` (DM request pending when `INVITED`).
    var membershipState: String?
    
    var displayTitle: String {
        if let email, !email.isEmpty { return email }
        if let displayName, !displayName.isEmpty { return displayName }
        return id
    }

    /// Whether this membership represents a DM request that has not yet been accepted.
    var isPendingRequest: Bool { membershipState == "INVITED" }
}
