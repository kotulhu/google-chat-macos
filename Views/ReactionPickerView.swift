import SwiftUI

struct ReactionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void
    
    @State private var searchText = ""
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
    
    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// A picker grid for selecting an emoji reaction across the full Unicode
    /// emoji set, grouped into categories.  The search field filters by glyph
    /// or CLDR keyword; category headers resolve through localization.
    var body: some View {
        VStack(spacing: 12) {
            Text(L.str("reaction.picker.title"))
                .font(.headline)
                .padding(.top, 16)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L.str("reaction.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            ScrollView {
                if query.isEmpty {
                    categoryBrowser
                } else {
                    resultsGrid
                }
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
    
    @ViewBuilder private var categoryBrowser: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(ReactionEmojis.categories, id: \.name) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.str("category." + category.name))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    
                    emojiGrid(category.emojis)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder private var resultsGrid: some View {
        let matches = ReactionEmojis.matches(query)
        if matches.isEmpty {
            Text(L.str("reaction.search.empty"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 32)
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text("\"\(query)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                emojiGrid(matches)
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder private func emojiGrid(_ emojis: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
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