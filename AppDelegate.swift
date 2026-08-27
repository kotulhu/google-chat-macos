import Cocoa
import GoogleSignIn
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    
    /// App-level delegate: finishes launch setup, registers the OAuth URL
    /// handler and the notification authorization.
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
}
