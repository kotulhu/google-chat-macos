import SwiftUI
import AppKit

struct MessageInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }
    
    private static let minHeight: CGFloat = 36
    private static let maxHeight: CGFloat = 120
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 100, height: Self.minHeight)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.minHeight))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: Self.maxHeight)
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        DispatchQueue.main.async {
            context.coordinator.reportHeight()
        }
    }
    
    static func contentHeight(for textView: NSTextView) -> CGFloat {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        let height = usedHeight + textView.textContainerInset.height * 2 + 2
        return min(max(height, minHeight), maxHeight)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageInputTextView
        weak var textView: NSTextView?
        
        init(_ parent: MessageInputTextView) {
            self.parent = parent
        }
        
        func reportHeight() {
            guard let textView = textView else { return }
            parent.onHeightChange(MessageInputTextView.contentHeight(for: textView))
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onHeightChange(MessageInputTextView.contentHeight(for: textView))
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                if modifiers.contains(.control) {
                    textView.insertNewline(nil)
                    return true
                }
                parent.onSend()
                return true
            }
            return false
        }
    }
}
