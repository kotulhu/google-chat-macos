import SwiftUI

/// A circular avatar: loads the user's picture when available, otherwise
/// falls back to the first letter of the display name.
struct AvatarImage: View {
    let url: URL?
    let name: String

    var body: some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Placeholder()
            }
            .clipShape(Circle())
        } else {
            Placeholder()
        }
    }

    /// The letter-initial fallback shown without a remote picture.
    private func Placeholder() -> some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
