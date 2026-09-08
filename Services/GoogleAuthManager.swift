import Foundation
import GoogleSignIn
import AppKit

/// Owns the Google Sign-In session: configuration, scopes, sign in/out and
/// periodic token refresh. Publishes the signed-in state, profile and the
/// current access token for the rest of the app.
class GoogleAuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var userEmail = ""
    @Published var userName = ""
    @Published var accessToken = ""

    /// Runs a block on the main thread (no-op if already there).
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Applies the OAuth client configuration to the shared sign-in instance.
    func configure() {
        let config = GIDConfiguration(clientID: ConfigManager.shared.clientID)
        GIDSignIn.sharedInstance.configuration = config
    }

    /// Presents the Google sign-in window with all required Chat/People scopes
    /// and reports success (with the account e-mail) or an error message.
    func signIn(completion: @escaping (Bool, String) -> Void) {
        print("➡️ signIn() called")
        guard let window = NSApplication.shared.windows.first else {
            completion(false, L.str("window.notFound"))
            return
        }
        print("✅ Found window: \(window)")
        
        let additionalScopes = [
            "https://www.googleapis.com/auth/chat.spaces.readonly",
            "https://www.googleapis.com/auth/chat.messages.readonly",
            "https://www.googleapis.com/auth/chat.messages.create",
            "https://www.googleapis.com/auth/chat.messages",
            "https://www.googleapis.com/auth/chat.spaces.create",
            "https://www.googleapis.com/auth/contacts.readonly",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/chat.memberships",
            "https://www.googleapis.com/auth/chat.messages.reactions"

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
                    completion(false, L.str("signin.noResult"))
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

    /// Signs the user out of Google and resets the published state.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        runOnMain {
            self.isSignedIn = false
            self.userEmail = ""
            self.userName = ""
            self.accessToken = ""
            print("👋 Sign out completed")
        }
    }

    /// Refreshes the Google access token in the background, publishing the new
    /// value; returns whether a usable token is available.
    func refreshAccessToken() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                continuation.resume(returning: false)
                return
            }
            
            print("🔄 Calling refreshTokensIfNeeded...")
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
