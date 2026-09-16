import Foundation

/// A People-API-resolved user profile (display name + optional photo + email).
struct ResolvedProfile: Codable, Equatable {
    let displayName: String?
    let photoURL: String?
    let email: String?
}
