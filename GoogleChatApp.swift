import SwiftUI
import GoogleSignIn
import AppKit

@main
struct ChatSandboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = GoogleAuthManager()
    @State private var showAbout = false
    
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
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О программе") {
                    showAbout = true
                }
            }
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
