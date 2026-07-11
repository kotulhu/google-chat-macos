import SwiftUI
import GoogleSignIn
import AppKit

@main
struct ChatSandboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = GoogleAuthManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    print("📲 onOpenURL получен URL: \(url.absoluteString)")
                    let handled = GIDSignIn.sharedInstance.handle(url)
                    print("📲 GoogleSignIn.handle вернул: \(handled)")
                }
                .onAppear {
                    authManager.configure()
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
