import SwiftUI

struct MentionAutocompleteView: View {
    let users: [ChatUser]
    let onSelect: (ChatUser) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(users.prefix(8)) { user in
                Button {
                    onSelect(user)
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayTitle)
                                .lineLimit(1)
                            if let email = user.email, email != user.displayTitle {
                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        )
        .cornerRadius(8)
        .shadow(radius: 8)
    }
}
