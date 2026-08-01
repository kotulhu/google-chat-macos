import Foundation

struct ChatUser: Identifiable, Hashable, Codable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarURL: URL?
    var membershipName: String?
    
    var displayTitle: String {
        if let email, !email.isEmpty {
            return email
        }
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return id
    }
}
