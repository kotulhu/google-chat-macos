import SwiftUI

struct MemberManagementView: View {
    /// The space whose membership this sheet manages.
    let space: ChatSpace
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [ChatUser] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    /// IDs of users that already belong to the current space.
    private var memberIds: Set<String> {
        Set(chatVM.currentSpaceMembers.map { $0.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.str("members.title"))
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                TextField(L.str("member.search.placeholder"), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchQuery) { _ in
                        scheduleSearch()
                    }
                Button(L.str("search")) {
                    scheduleSearch(immediate: true)
                }
            }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else if !searchQuery.isEmpty && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.str("add.member.header"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(searchResults) { user in
                        HStack {
                            AvatarImage(url: user.avatarURL, name: user.displayTitle)
                                .frame(width: 24, height: 24)
                            Text(user.displayTitle)
                                .lineLimit(1)
                            Spacer()
                            if memberIds.contains(user.id) {
                                Text(L.str("already.in.chat"))
                                    .foregroundColor(.secondary)
                            } else {
                                Button(L.str("add")) {
                                    addMember(user)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            } else if !searchQuery.isEmpty {
                Text(L.str("no.results"))
                    .foregroundColor(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chatVM.currentSpaceMembers) { member in
                        HStack {
                            AvatarImage(url: member.avatarURL, name: member.displayTitle)
                                .frame(width: 24, height: 24)
                            Text(member.displayTitle)
                                .lineLimit(1)
                            Spacer()
                            if member.id == chatVM.myUserId {
                                Text(L.str("you"))
                                    .foregroundColor(.secondary)
                            } else {
                                Button(L.str("remove"), role: .destructive) {
                                    removeMember(member)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
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
                    Label(L.str("leave.chat"), systemImage: "arrow.left.circle")
                }
            }
        }
        .padding()
        .frame(width: 420, height: 520)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    /// Schedules a (debounced) user search; `immediate` bypasses the delay.
    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            isSearching = true
            let results = await chatVM.searchUsers(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }
    
    /// Adds the found user to the space as a member and clears the search.
    private func addMember(_ user: ChatUser) {
        Task {
            await chatVM.addMember(user, to: space.id)
            searchQuery = ""
            searchResults = []
        }
    }

    /// Removes a member from the space.
    private func removeMember(_ member: ChatUser) {
        Task {
            await chatVM.removeMember(member, from: space.id)
        }
    }

    /// Makes the current user leave the space and closes the sheet.
    private func leaveChat() {
        Task {
            await chatVM.leaveSpace(space.id)
            dismiss()
        }
    }
}

/// A circular avatar: loads the user's picture when available, otherwise
    /// falls back to the first letter of the display name.
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
