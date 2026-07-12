import Foundation
import SwiftUI

extension String {
    func attributedStringWithLinks(mentionDisplayNames: [String: String] = [:]) -> AttributedString {
        let displayText = replacingMentions(with: mentionDisplayNames)
        var attributedString = AttributedString(displayText)
        displayText.highlightMentions(in: &attributedString, mentionDisplayNames: mentionDisplayNames)
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsRange = NSRange(location: 0, length: displayText.utf16.count)
        
        detector?.enumerateMatches(in: displayText, options: [], range: nsRange) { match, _, _ in
            guard let match = match, let url = match.url else { return }
            if let range = Range(match.range, in: displayText) {
                let startIndex = AttributedString.Index(range.lowerBound, within: attributedString)!
                let endIndex = AttributedString.Index(range.upperBound, within: attributedString)!
                let attributedRange = startIndex..<endIndex
                
                attributedString[attributedRange].link = url
                attributedString[attributedRange].foregroundColor = .blue
                attributedString[attributedRange].underlineStyle = .single
            }
        }
        
        return attributedString
    }

    private func replacingMentions(with mentionDisplayNames: [String: String]) -> String {
        var result = self
        for (userId, displayName) in mentionDisplayNames.sorted(by: { $0.key.count > $1.key.count }) {
            let mention = "<\(userId)>"
            result = result.replacingOccurrences(of: mention, with: "@\(displayName)")
        }
        return result
    }

    private func highlightMentions(in attributedString: inout AttributedString, mentionDisplayNames: [String: String]) {
        guard let regex = try? NSRegularExpression(pattern: #"<users/[^>]+>"#) else {
            return
        }
        
        let nsRange = NSRange(location: 0, length: utf16.count)
        regex.enumerateMatches(in: self, range: nsRange) { match, _, _ in
            guard let match, let range = Range(match.range, in: self),
                  let startIndex = AttributedString.Index(range.lowerBound, within: attributedString),
                  let endIndex = AttributedString.Index(range.upperBound, within: attributedString) else {
                return
            }
            
            let attributedRange = startIndex..<endIndex
            attributedString[attributedRange].foregroundColor = .orange
            attributedString[attributedRange].font = .body.bold()
        }
        
        for displayName in mentionDisplayNames.values {
            let mention = "@\(displayName)"
            guard let range = range(of: mention),
                  let startIndex = AttributedString.Index(range.lowerBound, within: attributedString),
                  let endIndex = AttributedString.Index(range.upperBound, within: attributedString) else {
                continue
            }
            
            let attributedRange = startIndex..<endIndex
            attributedString[attributedRange].foregroundColor = .orange
            attributedString[attributedRange].font = .body.bold()
        }
    }
}
