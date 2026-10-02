import AppKit
import SwiftUI

/// A circular avatar: loads the user's picture through `AvatarCache` (24-hour
/// memory + disk cache) when available, otherwise falls back to the first
/// letter of the display name.
struct AvatarImage: View {
    let url: URL?
    let name: String
    var accessToken: String? = nil

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Placeholder()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(Circle())
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await AvatarCache.shared.image(for: url, accessToken: accessToken)
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
