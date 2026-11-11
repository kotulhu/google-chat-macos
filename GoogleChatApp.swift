import SwiftUI
import GoogleSignIn
import AppKit

/// Posted when the user chooses the Debug → Dump reactions report menu item.
extension Notification.Name {
    static let dumpReactionsReport = Notification.Name("dumpReactionsReport")
}

@main
struct ChatSandboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = GoogleAuthManager()
    @State private var showAbout = false
    
    /// The application entry point: owns the window group, the settings scene
    /// and the app menu commands (About / Settings).
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    print("📲 onOpenURL received URL: \(url.absoluteString)")
                    let handled = GIDSignIn.sharedInstance.handle(url)
                    print("📲 GoogleSignIn.handle returned: \(handled)")
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
                Button(L.str("about")) {
                    showAbout = true
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(L.str("settings")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            #if DEBUG
            CommandGroup(after: .appSettings) {
                Section("Debug") {
                    Button("Dump reactions report") {
                        NotificationCenter.default.post(name: .dumpReactionsReport, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                }
            }
            #endif
        }
        
        Settings {
            SettingsView()
        }
    }
}
