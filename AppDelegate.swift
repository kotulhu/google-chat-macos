import Cocoa
import GoogleSignIn
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {

    /// Owns the window close handler for its whole lifetime (the window's
    /// `delegate` property is weak, so the strong reference is required).
    private var windowCloseDelegate: WindowCloseDelegate?

    /// App-level delegate: finishes launch setup, registers the OAuth URL
    /// handler and the notification authorization. Also swaps the window close
    /// button to minimize instead of quitting.
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ AppDelegate: applicationDidFinishLaunching")
        
        let appleEventManager = NSAppleEventManager.shared()
        appleEventManager.setEventHandler(self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("✅ Notifications allowed")
            }
        }

        // Attach the close→minimize handler as soon as the SwiftUI window is
        // materialized (the WindowGroup window appears right after launch).
        let closeDelegate = WindowCloseDelegate()
        windowCloseDelegate = closeDelegate
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.delegate = closeDelegate
            }
        }
    }
    
    /// Forwards a Google OAuth redirect URL to the Google Sign-In framework.
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor?, withReplyEvent replyEvent: NSAppleEventDescriptor?) {
        if let urlString = event?.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Decides how a notification is presented while the app is in the
    /// foreground: banner, sound and badge are all shown.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        print("🔔 willPresent: title=\"\(content.title)\" body=\"\(content.body.prefix(60))\" sound=\(content.sound != nil)")
        
        completionHandler([.alert, .sound, .badge])
    }

    /// Handles a click on a delivered notification: restores the window to the
    /// front and routes to the chat whose space id was stored in the payload.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let spaceID = userInfo["spaceId"] as? String else {
            print("🔔 didReceive: notification has no spaceId")
            completionHandler()
            return
        }

        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .openSpaceFromNotification, object: nil, userInfo: ["spaceId": spaceID])
        }
        completionHandler()
    }
}
