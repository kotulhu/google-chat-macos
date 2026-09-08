import SwiftUI

/// The root view of the app.
///
/// Shows the login screen while the user is signed out and the main chat
/// interface as soon as authentication succeeds.
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
                .onReceive(NotificationCenter.default.publisher(for: .openSpaceFromNotification)) { note in
                    guard let spaceID = note.userInfo?["spaceId"] as? String else { return }
                    chatVM.openSpace(withID: spaceID)
                }
        }
    }

    /// The sign-in screen shown before a Google account is connected.
    var loginView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Google Chat Client")
                .font(.largeTitle)
                .bold()

            Text(L.str("login.prompt"))
                .foregroundColor(.secondary)

            if isAuthenticating {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Button(L.str("login.button")) {
                    print("🔘 Login button clicked")
                    isAuthenticating = true
                    authManager.configure()
                    authManager.signIn { success, emailOrError in
                        isAuthenticating = false
                        if success {
                            print("✅ Sign in succeeded")
                            self.chatVM.startBackgroundCheck()
                            self.chatVM.sendWelcomeNotification()
                            self.chatVM.configure(with: self.authManager.accessToken, authManager: self.authManager)
                            self.chatVM.startTokenRefreshTimer(authManager: self.authManager)
                            Task {
                                await self.chatVM.loadSpaces()
                            }
                        } else {
                            print("❌ Error: \(emailOrError)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 400, height: 300)
    }
    
    /// The authenticated chat interface: a space list on the left and the
    /// detail pane on the right.
    var mainChatView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L.str("filter.placeholder"), text: $spaceFilterText)
                        .textFieldStyle(.plain)
                    if !spaceFilterText.isEmpty {
                        Button {
                            spaceFilterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help(L.str("filter.clear"))
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
                        Text(spaceFilterText.isEmpty ? L.str("no.chats") : L.str("nothing.found"))
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
                    .help(L.str("new.chat"))
                }
                ToolbarItem {
                    HStack {
                        Text(authManager.userEmail)
                            .font(.caption)
                        Button(L.str("sign.out")) {
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
                    L.str("select.chat"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L.str("select.chat.hint"))
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

    /// Spaces that match the current sidebar filter query.
    private var filteredSpaces: [ChatSpace] {
        let query = spaceFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chatVM.spaces }
        return chatVM.spaces.filter {
            $0.name.localizedStandardContains(query)
        }
    }
}

/// The detail pane for a single chat: message list, attachment strip,
/// mention autocomplete and the message input bar.
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
    @State private var inputHeight: CGFloat = 36
    @State private var isShowingMembers = false
    @State private var editingMessage: Message?
    @State private var editingText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(space.name)
                    .font(.headline)
                
                Spacer()
                
                if space.type != .direct {
                    Button {
                        isShowingMembers = true
                    } label: {
                        Label(L.str("members.toolbar", String(memberEmails.count)), systemImage: "person.2")
                    }
                    .help(L.str("members.help"))
                    .sheet(isPresented: $isShowingMembers) {
                        MemberManagementView(space: space, chatVM: chatVM)
                    }
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
                                },
                                onEdit: { message in
                                    editingMessage = message
                                    editingText = message.text
                                },
                                onDelete: { message in
                                    Task { await chatVM.deleteMessage(message) }
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
                    PerfBeacon.mark("Render", phase: "messagesChanged", detail: "count=\(chatVM.messages.count)")
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
            
            Group {
                if let msg = editingMessage {
                HStack {
                    TextField(L.str("edit.placeholder"), text: $editingText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveEditedMessage(msg) }
                    Button(L.str("save")) {
                        saveEditedMessage(msg)
                    }
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    Button(L.str("cancel")) {
                        editingMessage = nil
                    }
                }
            } else {
                HStack {
                Button(action: selectFiles) {
                    Image(systemName: selectedFiles.isEmpty ? "paperclip" : "paperclip.badge.ellipsis")
                }
                .help(L.str("attach.files"))
                
                MessageInputTextView(
                    text: $newMessageText,
                    onSend: { sendInputMessage() },
                    onHeightChange: { height in
                        inputHeight = height
                    }
                )
                .frame(height: inputHeight)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    Group {
                        if newMessageText.isEmpty && selectedFiles.isEmpty {
                            Text(L.str("message.placeholder"))
                                .font(.body)
                                .foregroundColor(Color.secondary.opacity(0.7))
                                .padding(.horizontal, 13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .leading
                )
                .onChange(of: newMessageText) { text in
                    updateMentionQuery(from: text)
                }
                .onAppear {
                    Task { await chatVM.loadMembers(for: space.id) }
                }
                
                Button(L.str("send")) {
                    sendInputMessage()
                }
                .disabled((newMessageText.isEmpty && selectedFiles.isEmpty) || chatVM.isSending)
                .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .top)
        }
    }
    
    /// Saves the edited text of a message through the view model, exiting edit
    /// mode only after the API confirms the update.
    private func saveEditedMessage(_ message: Message) {
        Task {
            if await chatVM.updateMessage(message, text: editingText) {
                editingMessage = nil
            }
        }
    }

    /// Uploads any selected attachments and sends the composed message,
    /// then clears the input and scrolls to the newest row.
    private func sendInputMessage() {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !selectedFiles.isEmpty else { return }
        guard !chatVM.isSending else { return }
        chatVM.isSending = true
        Task {
            defer { chatVM.isSending = false }
            var attachmentUploadTokens: [String] = []
            var uploadFailed = false
            for fileURL in selectedFiles {
                do {
                    let uploadToken = try await chatVM.uploadFile(fileURL: fileURL, to: space.id)
                    attachmentUploadTokens.append(uploadToken)
                } catch {
                    uploadFailed = true
                    print("Failed to upload \(fileURL.lastPathComponent): \(error)")
                }
            }
            if uploadFailed {
                return
            }
            let sent = await chatVM.sendMessage(text, attachments: attachmentUploadTokens)
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
    
    /// Performs the one-time initial scroll towards the last-read message
    /// for the current space, using a short stability window so later
    /// layout changes do not trigger repeated jumps.
    private func scrollToInitialMessage(using proxy: ScrollViewProxy) {
        guard !didInitialScroll, let target = chatVM.initialScrollTarget(for: space.id) else {
            return
        }
        
        initialScrollTarget = target
        stabilizeInitialScrollUntil = Date().addingTimeInterval(2.5)
        didInitialScroll = true
        PerfBeacon.mark("Render", phase: "initialScroll", detail: "id=\(target.id.suffix(12))")
        stabilizeInitialScroll(using: proxy)
    }

    /// Re-applies the initial scroll anchor a few times while the layout is
    /// still stabilizing (e.g. while attachments or reactions finish loading).
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
    
    /// Tracks the word following the last "@" in the input so the mention
    /// autocomplete list can be shown while the user is typing a mention.
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
    
    /// Users of the current space that match the mention query by name or email.
    private func filteredMentionUsers(query: String) -> [ChatUser] {
        let lowercasedQuery = query.lowercased()
        return chatVM.currentSpaceMembers.filter { user in
            lowercasedQuery.isEmpty
                || user.displayTitle.lowercased().contains(lowercasedQuery)
                || (user.email?.lowercased().contains(lowercasedQuery) == true)
        }
    }
    
    /// Resolves the display title shown for every space member mention.
    private var mentionDisplayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: chatVM.currentSpaceMembers.map { user in
            (user.id, user.displayTitle)
        })
    }
    
    /// Unique, sorted list of e-mails (or display titles) of the space members.
    private var memberEmails: [String] {
        Array(Set(chatVM.currentSpaceMembers
            .map { user in user.email?.isEmpty == false ? user.email! : user.displayTitle }
            .filter { !$0.isEmpty })
        )
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Replaces the "@query" suffix with a formatted chat mention tag.
    private func insertMention(_ user: ChatUser) {
        guard let atIndex = newMessageText.lastIndex(of: "@") else { return }
        newMessageText.replaceSubrange(atIndex..<newMessageText.endIndex, with: "<\(user.id)> ")
        mentionQuery = nil
    }
    
    /// Presents the system file picker and stores the chosen files as pending
    /// attachments for the next message.
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
