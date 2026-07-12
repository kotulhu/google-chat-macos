import Foundation
import GoogleSignIn
import AppKit

class GoogleAuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var userEmail = ""
    @Published var userName = ""
    @Published var accessToken = ""

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    func configure() {
        let config = GIDConfiguration(clientID: ConfigManager.shared.clientID)
        GIDSignIn.sharedInstance.configuration = config
    }
    
    func signIn(completion: @escaping (Bool, String) -> Void) {
        print("➡️ signIn() вызван")
        guard let window = NSApplication.shared.windows.first else {
            completion(false, "Окно не найдено")
            return
        }
        print("✅ Найдено окно: \(window)")
        
        let additionalScopes = [
            "https://www.googleapis.com/auth/chat.spaces.readonly",
            "https://www.googleapis.com/auth/chat.messages.readonly",
            "https://www.googleapis.com/auth/chat.messages.create",
            "https://www.googleapis.com/auth/chat.spaces.create",
            "https://www.googleapis.com/auth/contacts.readonly",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/chat.memberships.readonly"

        ]
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: additionalScopes
        ) { result, error in
            if let error = error {
                let message = error.localizedDescription
                self.runOnMain {
                    completion(false, message)
                }
                return
            }
            
            guard let result = result else {
                self.runOnMain {
                    completion(false, "Результат отсутствует")
                }
                return
            }
            
            let user = result.user
            let email = user.profile?.email ?? ""
            let name = user.profile?.name ?? ""
            let token = user.accessToken.tokenString

            self.runOnMain {
                self.isSignedIn = true
                self.userEmail = email
                self.userName = name
                self.accessToken = token

                completion(true, email)
            }
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        runOnMain {
            self.isSignedIn = false
            self.userEmail = ""
            self.userName = ""
            self.accessToken = ""
            print("👋 Выход выполнен")
        }
    }
    
    func refreshAccessToken() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                continuation.resume(returning: false)
                return
            }
            
            print("🔄 Вызов refreshTokensIfNeeded...")
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error = error {
                    continuation.resume(returning: false)
                    return
                }
                
                let token = refreshedUser?.accessToken.tokenString ?? ""
                self.runOnMain {
                    self.accessToken = token
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
