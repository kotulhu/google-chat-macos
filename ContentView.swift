import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = GoogleAuthManager()
    @StateObject private var chatVM = ChatViewModel()
    @State private var newMessageText = ""
    @State private var isAuthenticating = false
    @State private var isCreateChatOpen = false
    @State private var spaceFilterText = ""
    
    var body: some View {
        if !authManager.isSignedIn {
            loginView
        } else {
            mainChatView
                .onAppear {
                    if chatVM.spaces.isEmpty && !authManager.accessToken.isEmpty {
                        chatVM.configure(with: authManager.accessToken, authManager: authManager)
                        Task {
                            await chatVM.loadSpaces()
                        }
                    }
                }
        }
    }
    
    var loginView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Google Chat Client")
                .font(.largeTitle)
                .bold()
            
            Text("Войдите, чтобы начать общение")
                .foregroundColor(.secondary)
            
            if isAuthenticating {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Button("Войти через Google") {
                    print("🔘 Кнопка нажата")
                    isAuthenticating = true
                    authManager.configure()
                    authManager.signIn { success, emailOrError in
                        isAuthenticating = false
                        if success {
                            print("✅ Успешный вход")
                            self.chatVM.startBackgroundCheck()
                            self.chatVM.sendWelcomeNotification()
                            self.chatVM.configure(with: self.authManager.accessToken, authManager: self.authManager)
                            self.chatVM.startTokenRefreshTimer(authManager: self.authManager)
                            Task {
                                await self.chatVM.loadSpaces()
                            }
                        } else {
                            print("❌ Ошибка: \(emailOrError)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 400, height: 300)
    }
    
    var mainChatView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Фильтр по названию", text: $spaceFilterText)
                        .textFieldStyle(.plain)
                    if !spaceFilterText.isEmpty {
                        Button {
                            spaceFilterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Очистить фильтр")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(Divider(), alignment: .bottom)

                List(selection: $chatVM.selectedSpace) {
                    if chatVM.isLoading && chatVM.spaces.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if filteredSpaces.isEmpty {
                        Text(spaceFilterText.isEmpty ? "Нет чатов" : "Ничего не найдено")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredSpaces) { space in
                            HStack {
                                Image(systemName: iconForSpace(space))
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.name)
                                        .font(.body)
                                    if let lastMsg = space.lastMessage {
                                        Text(lastMsg)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if space.unreadCount > 0 {
                                    Text("\(space.unreadCount)")
                                        .font(.caption)
                                        .padding(6)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                }
                            }
                            .tag(space)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Button {
                        isCreateChatOpen = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("Новый чат")
                }
                ToolbarItem {
                    HStack {
                        Text(authManager.userEmail)
                            .font(.caption)
                        Button("Выйти") {
                            authManager.signOut()
                            chatVM.clearData()
                            chatVM.stopTokenRefreshTimer()
                            chatVM.stopBackgroundCheck()
                        }
                        .font(.caption)
                    }
                }
            }
            .sheet(isPresented: $isCreateChatOpen) {
                CreateChatView(chatVM: chatVM)
            }
            .onChange(of: chatVM.selectedSpace) { newSpace in
                if let space = newSpace {
                    chatVM.stopPolling()
                    chatVM.messages = []
                    chatVM.currentSpaceMembers = []
                    Task {
                        await chatVM.loadMessages(for: space)
                        if space.type != .direct {
                            await chatVM.loadMembers(for: space.id)
                        }
                        await MainActor.run {
                            chatVM.startPolling(for: space)
                        }
                    }
                } else {
                    chatVM.stopPolling()
                }
            }
        } detail: {
            if let space = chatVM.selectedSpace {
                ChatDetailView(space: space, chatVM: chatVM)
                    .id(space.id)
            } else {
                ContentUnavailableView(
                    "Выберите чат",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Нажмите на чат слева, чтобы начать переписку")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    private func iconForSpace(_ space: ChatSpace) -> String {
        switch space.type {
        case .channel: return "number"
        case .direct: return "person"
        case .group: return "person.3"
        }
    }

    private var filteredSpaces: [ChatSpace] {
        let query = spaceFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chatVM.spaces }
        return chatVM.spaces.filter {
            $0.name.localizedStandardContains(query)
        }
    }
}

struct ChatDetailView: View {
    let space: ChatSpace
    @ObservedObject var chatVM: ChatViewModel
    @State private var newMessageText = ""
    @State private var selectedFiles: [URL] = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var didInitialScroll = false
    @State private var initialScrollTarget: (id: String, anchor: UnitPoint)?
    @State private var isStabilizingInitialScroll = false
    @State private var stabilizeInitialScrollUntil: Date?
    @State private var mentionQuery: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(space.name)
                    .font(.headline)
                
                Spacer()
                
                if space.type != .direct {
                    Menu {
                        if memberEmails.isEmpty {
                            Text("Нет данных")
                        } else {
                            ForEach(memberEmails, id: \.self) { email in
                                Text(email)
                            }
                        }
                    } label: {
                        Label("Участники \(memberEmails.count)", systemImage: "person.2")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Участники чата")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            .task(id: space.id) {
                if space.type != .direct {
                    await chatVM.loadMembers(for: space.id)
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chatVM.messages.reversed()) { message in
                            MessageBubbleView(
                                message: message,
                                accessToken: chatVM.accessToken,
                                onSenderTap: { userId in
                                    Task { await chatVM.openDirectChat(with: userId) }
                                },
                                mentionDisplayNames: mentionDisplayNames,
                                onAttachmentLayoutChanged: {
                                    stabilizeInitialScroll(using: proxy)
                                },
                                onViewportVisible: { messageId in
                                    chatVM.markReactionViewportVisible(id: messageId)
                                },
                                onViewportHidden: { messageId in
                                    chatVM.markReactionViewportHidden(id: messageId)
                                },
                                onToggleReaction: { messageId, emoji in
                                    await chatVM.toggleReaction(messageId: messageId, emoji: emoji)
                                }
                            )
                                .id(message.id)
                                .onAppear {
                                    chatVM.markMessageAsRead(message, in: space.id)
                                }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToInitialMessage(using: proxy)
                }
                .onChange(of: chatVM.messages) { _ in
                    scrollToInitialMessage(using: proxy)
                }
            }
            if let mentionQuery,
               !filteredMentionUsers(query: mentionQuery).isEmpty {
                MentionAutocompleteView(users: filteredMentionUsers(query: mentionQuery)) { user in
                    insertMention(user)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            
            if !selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent)
                                    .lineLimit(1)
                                Button {
                                    selectedFiles.removeAll { $0 == file }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 40)
            }
            
            HStack {
                Button(action: selectFiles) {
                    Image(systemName: selectedFiles.isEmpty ? "paperclip" : "paperclip.badge.ellipsis")
                }
                .help("Прикрепить файлы")
                
                TextField("Сообщение...", text: $newMessageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: newMessageText) { text in
                        updateMentionQuery(from: text)
                    }
                    .onAppear {
                        Task { await chatVM.loadMembers(for: space.id) }
                    }
                
                Button("Отправить") {
                    guard !newMessageText.isEmpty || !selectedFiles.isEmpty else { return }
                    Task {
                        var attachmentUploadTokens: [String] = []
                        var uploadFailed = false
                        for fileURL in selectedFiles {
                            do {
                                let uploadToken = try await chatVM.uploadFile(fileURL: fileURL, to: space.id)
                                attachmentUploadTokens.append(uploadToken)
                            } catch {
                                uploadFailed = true
                                print("Ошибка загрузки \(fileURL.lastPathComponent): \(error)")
                            }
                        }
                        if uploadFailed {
                            return
                        }
                        let sent = await chatVM.sendMessage(newMessageText, attachments: attachmentUploadTokens)
                        guard sent else { return }
                        newMessageText = ""
                        selectedFiles = []
                        
                        if let firstId = chatVM.messages.first?.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    scrollProxy?.scrollTo(firstId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .disabled((newMessageText.isEmpty && selectedFiles.isEmpty))
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .top)
        }
    }
    
    private func scrollToInitialMessage(using proxy: ScrollViewProxy) {
        guard !didInitialScroll, let target = chatVM.initialScrollTarget(for: space.id) else {
            return
        }
        
        initialScrollTarget = target
        stabilizeInitialScrollUntil = Date().addingTimeInterval(2.5)
        didInitialScroll = true
        stabilizeInitialScroll(using: proxy)
    }

    private func stabilizeInitialScroll(using proxy: ScrollViewProxy) {
        guard let target = initialScrollTarget,
              let stabilizeInitialScrollUntil,
              Date() <= stabilizeInitialScrollUntil,
              !isStabilizingInitialScroll else {
            return
        }
        
        isStabilizingInitialScroll = true
        let delays: [TimeInterval] = [0.02, 0.08, 0.18, 0.35]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(target.id, anchor: target.anchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delays.last ?? 0.35) + 0.05) {
            isStabilizingInitialScroll = false
        }
    }
    
    private func updateMentionQuery(from text: String) {
        guard let atIndex = text.lastIndex(of: "@") else {
            mentionQuery = nil
            return
        }
        
        let query = String(text[text.index(after: atIndex)...])
        if query.contains(where: { $0.isWhitespace || $0 == "\n" }) {
            mentionQuery = nil
        } else {
            mentionQuery = query
        }
    }
    
    private func filteredMentionUsers(query: String) -> [ChatUser] {
        let lowercasedQuery = query.lowercased()
        return chatVM.currentSpaceMembers.filter { user in
            lowercasedQuery.isEmpty
                || user.displayTitle.lowercased().contains(lowercasedQuery)
                || (user.email?.lowercased().contains(lowercasedQuery) == true)
        }
    }
    
    private var mentionDisplayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: chatVM.currentSpaceMembers.map { user in
            (user.id, user.displayTitle)
        })
    }
    
    private var memberEmails: [String] {
        Array(Set(chatVM.currentSpaceMembers
            .map { user in user.email?.isEmpty == false ? user.email! : user.displayTitle }
            .filter { !$0.isEmpty })
        )
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private func insertMention(_ user: ChatUser) {
        guard let atIndex = newMessageText.lastIndex(of: "@") else { return }
        newMessageText.replaceSubrange(atIndex..<newMessageText.endIndex, with: "<\(user.id)> ")
        mentionQuery = nil
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK {
                selectedFiles = panel.urls
            }
        }
    }
}
