import Cocoa
import GoogleSignIn
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    
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
                print("✅ Уведомления разрешены")
            }
        }
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor?, withReplyEvent replyEvent: NSAppleEventDescriptor?) {
        if let urlString = event?.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        print("🔔 willPresent: title=\"\(content.title)\" body=\"\(content.body.prefix(60))\" sound=\(content.sound != nil)")
        
        completionHandler([.alert, .sound, .badge])
    }
}
