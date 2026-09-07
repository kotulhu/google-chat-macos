import AppKit

/// Window delegate that repurposes the window close button (and "Close"/Cmd+W)
/// to minimize the window instead of closing/quitting the app.
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    /// Turns a close request into a miniaturization and vetoes the close.
    /// App termination via the menu (Cmd+Q) is unaffected.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}