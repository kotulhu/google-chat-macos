import SwiftUI

struct MemberManagementView: View {
    let space: ChatSpace
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchQuery = ""
    @State private var searchResults: [ChatUser] = []
    @State private var isSearching = false
    
    private var memberIds: Set<String> {
        Set(chatVM.currentSpaceMembers.map { $0.id })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Участники")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                TextField("Имя или email…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button("Найти") { runSearch() }
            }
            
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else if !searchQuery.isEmpty && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(searchResults) { user in
                        HStack {
                            AvatarImage(url: user.avatarURL, name: user.displayTitle)
                                .frame(width: 24, height: 24)
                            Text(user.displayTitle)
                                .lineLimit(1)
                            Spacer()
                            if memberIds.contains(user.id) {
                                Text("В чате")
                                    .foregroundColor(.secondary)
                            } else {
                                Button("Добавить") {
                                    addMember(user)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            } else if !searchQuery.isEmpty {
                Text("Никого не найдено")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            List {
                ForEach(chatVM.currentSpaceMembers) { member in
                    HStack {
                        AvatarImage(url: member.avatarURL, name: member.displayTitle)
                            .frame(width: 24, height: 24)
                        Text(member.displayTitle)
                            .lineLimit(1)
                        Spacer()
                        if member.id == chatVM.myUserId {
                            Text("Вы")
                                .foregroundColor(.secondary)
                        } else {
                            Button("Удалить", role: .destructive) {
                                removeMember(member)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            
            if let error = chatVM.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            
            if space.type != .direct {
                Button(role: .destructive) {
                    leaveChat()
                } label: {
                    Label("Покинуть чат", systemImage: "arrow.left.circle")
                }
            }
        }
        .padding()
        .frame(width: 420, height: 500)
    }
    
    private func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchResults = []
        Task {
            searchResults = await chatVM.searchUsers(query: query)
            isSearching = false
        }
    }
    
    private func addMember(_ user: ChatUser) {
        Task {
            await chatVM.addMember(user, to: space.id)
            searchQuery = ""
            searchResults = []
        }
    }
    
    private func removeMember(_ member: ChatUser) {
        Task {
            await chatVM.removeMember(member, from: space.id)
        }
    }
    
    private func leaveChat() {
        Task {
            await chatVM.leaveSpace(space.id)
            dismiss()
        }
    }
}

private struct AvatarImage: View {
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
