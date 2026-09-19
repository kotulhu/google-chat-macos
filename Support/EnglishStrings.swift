import Foundation

/// English string table (default locale, also used as the fallback).
///
/// UI placeholders in the code reference these stable keys through `L.str(...)`.
public enum EnglishStrings {
    /// Key-value mapping shared with the localization coordinator (`L`).
    public static let dict: [String: String] = [
        // App menu
        "about": "About",
        "settings": "Settings...",
        "close": "Close",

        // Login screen
        "login.prompt": "Sign in to start chatting",
        "login.button": "Sign in with Google",

        // Sidebar / list
        "filter.placeholder": "Filter by name",
        "filter.clear": "Clear filter",
        "no.chats": "No chats",
        "nothing.found": "Nothing found",
        "new.chat": "New chat",
        "sign.out": "Sign out",

        // Chat detail / empty state
        "select.chat": "Select a chat",
        "select.chat.hint": "Click a chat on the left to start messaging",
        "members.toolbar": "Members %@",
        "members.help": "Chat members",
        "attach.files": "Attach files",
        "message.placeholder": "Message...",
        "send": "Send",
        "edit": "Edit",
        "delete": "Delete",
        "save": "Save",
        "edit.placeholder": "Edit message...",
        "jump.unread.hint": "Jump to first unread message",

        // Member management
        "members.title": "Members",
        "member.search.placeholder": "Name or email…",
        "search": "Search",
        "add.member.header": "Add member",
        "already.in.chat": "In chat",
        "add": "Add",
        "no.results": "No one found",
        "you": "You",
        "remove": "Remove",
        "leave.chat": "Leave chat",

        // Chat list
        "space.pin": "Pin to top",
        "space.unpin": "Unpin",

        // About
        "version.format": "Version %@ (build %@)",
        "developer": "Developer",
        "contact": "Contact",
        "unofficial.client.note": "Unofficial Google Chat client for macOS",
        "about.gogol.note": "Named in honor of the writer Nikolai Gogol.",

        // Create chat
        "new.chat.title": "New chat",
        "name": "Name",
        "type": "Type",
        "channel": "Channel",
        "group.chat": "Group chat",
        "cancel": "Cancel",
        "creating": "Creating...",
        "create": "Create",

        // Settings
        "display.name": "Display name",
        "settings.oauth.note": "OAuth Client ID is used for signing in. The Reversed Client ID is generated from it automatically and must match the value baked into the app (GOOGLE_REVERSED_CLIENT_ID in GoogleChat.local.xcconfig), because macOS registers the OAuth callback URL scheme from Info.plist at build time.",
        "settings.reversed.help": "Read-only – derived from the OAuth Client ID by reversing its dot-separated components.",

        // Reaction picker
        "reaction.picker.title": "Choose reaction",
        "reaction.search.placeholder": "Search emoji",
        "reaction.search.empty": "No emoji found",
        "category.smileys": "Smileys",
        "category.people": "Gestures & People",
        "category.animals": "Animals & Nature",
        "category.food": "Food & Drink",
        "category.activities": "Activities",
        "category.travel": "Travel & Places",
        "category.objects": "Objects",
        "category.symbols": "Symbols",
        "category.flags": "Flags",

        // Message bubble / attachments
        "copy.text": "Copy text",
        "quote": "Quote",
        "quote.original": "Message",
        "quote.remove": "Remove quote",
        "quote.jump": "Go to the original message",
        "more.reactions": "More reactions...",

        // Custom icons
        "add.custom.icon": "Add custom icon...",
        "add.custom.icon.title": "Add custom icon",
        "add.custom.icon.drop": "Drop an image here or click to choose",
        "add.custom.icon.choose": "Choose file...",
        "add.custom.icon.name": "Emoji name",
        "add.custom.icon.upload": "Upload",
        "add.custom.icon.uploading": "Uploading...",
        "add.custom.icon.success": "Icon uploaded",
        "add.custom.icon.animated": "animated",
        "add.custom.icon.error.pick": "Choose an image file first",
        "add.custom.icon.error.invalid": "Can't read this image",
        "add.custom.icon.error.duplicate": "This name is already taken — try a different one.",
        "add.custom.icon.scope.failed": "Access to custom emoji was not granted",
        "download": "Download",
        "loading": "Loading...",
        "load.failed": "Failed to load",
        "history.load.previous": "Load previous messages",
        "date.yesterday": "'Yesterday, ' HH:mm",

        // Errors / user-facing fallbacks
        "err.load.chats": "Failed to load chats: %@",
        "err.load.messages": "Failed to load messages: %@",
        "err.load.previous": "Failed to load previous messages: %@",
        "err.send": "Failed to send: %@",
        "err.send.permission": "Couldn't send: this user must accept the chat request first.",
        "dm.request.pending": "This user hasn't accepted the chat request yet. You'll be able to chat once they accept.",
        "err.create.chat": "Failed to create chat: %@",
        "err.open.chat": "Failed to open direct chat: %@",
        "err.add.member": "Failed to add member: %@",
        "err.remove.member": "Failed to remove member: %@",
        "err.remove.member.noData": "Failed to remove member: no membership data",
        "err.leave.chat": "Failed to leave chat: %@",
        "user.unknown": "User",
        "space.unnamed": "Untitled",
        "welcome.message": "Welcome!",
        "welcome.space": "Welcome",
        "membership.notFound": "Membership not found",
        "window.notFound": "No window found",
        "signin.noResult": "No sign-in result",

        // Archive export
        "general.ok": "OK",
        "export.menu": "Archive export",
        "export.current": "Export this chat to HTML",
        "export.all": "Export all chats to HTML",
        "export.panel.title": "Choose a folder to export the archive to",
        "export.choose": "Export here",
        "export.exporting": "Exporting archive…",
        "export.empty": "Nothing to export yet — open some chats first so they get archived",
        "export.doc.title": "Conversation archive — Google Chat",
        "export.doc.exported": "Exported %@",
        "export.doc.messages": "%@ messages",
        "export.doc.messages.updated": "Last activity %@",
        "export.doc.part": "Part %@ of %@",
        "export.doc.prev": "Previous part",
        "export.doc.next": "Next part",
        "export.doc.toc": "Contents",
        "export.doc.quote": "Quote",
        "export.link.original": "Source file",
        "export.missing": "not downloaded",
    ]
}