import SwiftUI

struct ReactionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
    
    /// A picker grid for selecting an emoji reaction, grouped into categories.
    ///
    /// Category headers resolve through the localization layer; the underlying
    /// `name` stays a stable English slug so list identity does not change
    /// with the active locale.
    var body: some View {
        VStack(spacing: 12) {
            Text(L.str("reaction.picker.title"))
                .font(.headline)
                .padding(.top, 16)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(ReactionEmojis.categories, id: \.name) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.str("category." + category.name))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    Button {
                                        onSelect(emoji)
                                    } label: {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Divider()
            
            Button(L.str("close")) {
                dismiss()
            }
            .keyboardShortcut(.escape)
            .padding(.bottom, 12)
        }
        .frame(width: 420, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

enum ReactionEmojis {
    /// A single grid group; `name` is a stable English slug used both as the
    /// list identity and as the localization key suffix.
    struct Category {
        let name: String
        let emojis: [String]
    }
    
    static let categories: [Category] = [
        Category(name: "smileys", emojis: [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣",
            "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰",
            "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜",
            "🤪", "🤨", "🧐", "🤓", "😎", "🥸", "🤩", "🥳",
            "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️",
            "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤",
            "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱",
            "😨", "😰", "😥", "😓", "🤗", "🤔", "🤭", "🤫",
            "🤥", "😶", "😐", "😑", "😬", "🙄", "😯", "😦",
            "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵",
            "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕",
            "🤑", "🤠", "😈", "👿", "👹", "👺", "🤡", "💩",
            "👻", "💀", "👽", "🤖", "🎃", "😺", "😸", "😹",
            "😻", "😼", "😽", "🙀", "😿", "😾"
        ]),
        Category(name: "people", emojis: [
            "👍", "👎", "👊", "✊", "🤛", "🤜", "👏", "🙌",
            "👐", "🤲", "🤝", "🙏", "✌️", "🤞", "🤟", "🤘",
            "🤙", "👌", "✋", "🤚", "🖐️", "🖖", "👋", "🤌",
            "🤏", "💪", "🦾", "🖕", "✍️", "👉", "👈", "👆",
            "👇", "☝️", "✋", "🫵", "🫶", "👀", "👁️", "🧠",
            "🫀", "🫁", "🦷", "🦴", "👅", "👄", "💋"
        ]),
        Category(name: "animals", emojis: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼",
            "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵",
            "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤",
            "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄",
            "🐝", "🐛", "🦋", "🐌", "🐞", "🐜", "🦟", "🦠",
            "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦀",
            "🐠", "🐟", "🐡", "🦈", "🐬", "🐳", "🐋", "🐊"
        ]),
        Category(name: "food", emojis: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇",
            "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥",
            "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶️",
            "🌽", "🥕", "🥔", "🍠", "🥐", "🥯", "🍞", "🥖",
            "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓",
            "🍔", "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🥙",
            "🍜", "🍝", "🍣", "🍤", "🍦", "🍧", "🍨", "🍩",
            "🍪", "🎂", "🍰", "🧁", "🍫", "🍬", "🍭", "🍮"
        ]),
        Category(name: "activities", emojis: [
            "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉",
            "🥏", "🎱", "🏓", "🏸", "🥅", "🏒", "🏑", "🥍",
            "🏏", "⛳", "🏹", "🎣", "🥊", "🥋", "🎽", "⛸️",
            "🛷", "🎿", "⛷️", "🏂", "🏋️", "🤼", "🤸", "🤺",
            "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊", "🤽", "🚣",
            "🧗", "🚵", "🚴", "🏆", "🥇", "🥈", "🥉", "🏅",
            "🎖️", "🏵️", "🎗️", "🎫", "🎟️", "🎪", "🤹", "🎭"
        ]),
        Category(name: "travel", emojis: [
            "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑",
            "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🏍️", "🛵",
            "🚲", "🛴", "🚨", "🚔", "🚍", "🚘", "🚖", "✈️",
            "🚀", "🛸", "⛵", "🚤", "🛥️", "🛳️", "⛴️", "🚢",
            "🚂", "🚃", "🚄", "🚅", "🚆", "🚇", "🚈", "🚉"
        ]),
        Category(name: "objects", emojis: [
            "⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "💽",
            "💾", "💿", "📀", "📷", "📸", "📹", "🎥", "📽️",
            "🎞️", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙️",
            "📚", "📖", "📕", "📗", "📘", "📙", "📌", "📎",
            "✂️", "🔑", "🔨", "🪓", "🔧", "🔩", "⚙️", "🧲",
            "💡", "🔦", "🔋", "🔌", "🖊️", "🖋️", "✏️", "📝"
        ]),
        Category(name: "symbols", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍",
            "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖",
            "💘", "💝", "💟", "♥️", "💯", "✅", "❌", "❓",
            "❗", "💢", "💥", "💫", "💦", "💨", "🕳️", "💣",
            "☄️", "🔥", "🌟", "⭐", "🌈", "☀️", "⛈️", "🌧️"
        ]),
        Category(name: "flags", emojis: [
            "🇺🇦", "🇺🇸", "🇬🇧", "🇫🇷", "🇩🇪", "🇪🇸", "🇮🇹", "🇵🇱",
            "🇨🇦", "🇯🇵", "🇨🇳", "🇮🇳", "🇧🇷", "🇹🇷", "🇳🇱", "🇵🇹"
        ])
    ]
}
