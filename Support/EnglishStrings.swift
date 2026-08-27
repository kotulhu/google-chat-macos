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

        // About
        "version.format": "Version %@ (build %@)",
        "developer": "Developer",
        "contact": "Contact",
        "unofficial.client.note": "Unofficial Google Chat client for macOS",

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
        "settings.oauth.note": "OAuth Client ID is used for signing in. The Reversed Client ID must match GOOGLE_REVERSED_CLIENT_ID in your local GoogleChat.local.xcconfig, because macOS registers the callback from Info.plist at build time.",

        // Reaction picker
        "reaction.picker.title": "Choose reaction",
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
        "more.reactions": "More reactions...",
        "download": "Download",
        "loading": "Loading...",
        "load.failed": "Failed to load",
        "date.yesterday": "'Yesterday, ' HH:mm",

        // Errors / user-facing fallbacks
        "err.load.chats": "Failed to load chats: %@",
        "err.load.messages": "Failed to load messages: %@",
        "err.send": "Failed to send: %@",
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
    ]
}