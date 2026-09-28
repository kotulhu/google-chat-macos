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

    /// Outcomes of the launch-time session check (`ensureAuthorized()`).
    enum AuthCheckResult: Equatable {
        /// A cached refresh token produced a usable access token.
        case authorized
        /// No refresh token (or it was rejected) — the interactive flow is needed.
        case needsSignIn
        /// A transient/network error: the cached credentials were kept, the user
        /// is offered a retry instead of an automatic sign-out.
        case failed(message: String)
    }

    /// Google token-endpoint errors. `invalid_grant` is the only one that means
    /// the cached refresh token is dead; the rest are treated as transient.
    private enum TokenExchangeError: LocalizedError, Equatable {
        case invalidGrant
        case invalidClient
        case server(message: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidGrant:
                return "Refresh token is no longer valid"
            case .invalidClient:
                return "OAuth client mismatch for token refresh"
            case .server(let message):
                return message
            case .malformedResponse:
                return "Malformed token response"
            }
        }
    }

    private static let cachedEmailKey = "authCachedEmail"
    private static let cachedNameKey = "authCachedName"

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
            "https://www.googleapis.com/auth/chat.messages.reactions",
            "https://www.googleapis.com/auth/chat.customemojis",
            "https://www.googleapis.com/auth/directory.readonly"
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

            let refreshToken = user.refreshToken.tokenString
            if !refreshToken.isEmpty {
                _ = KeychainTokenStore.saveRefreshToken(refreshToken)
                print("🔑 Refresh token cached in Keychain")
            }
            UserDefaults.standard.set(email, forKey: Self.cachedEmailKey)
            UserDefaults.standard.set(name, forKey: Self.cachedNameKey)

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
        KeychainTokenStore.deleteRefreshToken()
        runOnMain {
            self.isSignedIn = false
            self.userEmail = ""
            self.userName = ""
            self.accessToken = ""
            print("👋 Sign out completed")
        }
    }

    /// Ensures the `directory.readonly` scope is granted.  If the current
    /// session does not contain it (e.g. an older token), presents the
    /// incremental-consent dialog.  Returns `true` when the scope is available.
    func ensureDirectoryScopeIfNeeded() async -> Bool {
        let scope = "https://www.googleapis.com/auth/directory.readonly"

        if let granted = GIDSignIn.sharedInstance.currentUser?.grantedScopes,
           granted.contains(scope) {
            print("✅ directory.readonly scope already granted")
            return true
        }

        guard let user = GIDSignIn.sharedInstance.currentUser,
              let window = NSApplication.shared.windows.first else {
            print("⚠️ ensureDirectoryScope: no user or window")
            return false
        }

        return await withCheckedContinuation { continuation in
            user.addScopes([scope], presenting: window) { _, error in
                if let error = error {
                    print("⚠️ addScopes failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                let granted = user.grantedScopes?.contains(scope) ?? false
                print(granted ? "✅ directory.readonly scope granted" : "⚠️ scope still missing after consent")
                continuation.resume(returning: granted)
            }
        }
    }

    /// Ensures the `chat.customemojis` scope is granted.  If the current
    /// session does not contain it, presents the incremental-consent dialog.
    /// Returns `true` when the scope is available.
    func ensureCustomEmojiScopeIfNeeded() async -> Bool {
        let scope = "https://www.googleapis.com/auth/chat.customemojis"

        if let granted = GIDSignIn.sharedInstance.currentUser?.grantedScopes,
           granted.contains(scope) {
            print("✅ chat.customemojis scope already granted")
            return true
        }

        guard let user = GIDSignIn.sharedInstance.currentUser,
              let window = NSApplication.shared.windows.first else {
            print("⚠️ ensureCustomEmojiScope: no user or window")
            return false
        }

        return await withCheckedContinuation { continuation in
            user.addScopes([scope], presenting: window) { _, error in
                if let error = error {
                    print("⚠️ addScopes failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                let granted = user.grantedScopes?.contains(scope) ?? false
                print(granted ? "✅ chat.customemojis scope granted" : "⚠️ scope still missing after consent")
                continuation.resume(returning: granted)
            }
        }
    }

    /// Decides whether the interactive OAuth flow is needed at all:
    ///
    /// 1. If a refresh token is cached in the Keychain, it is silently exchanged
    ///    for a fresh access token at the OAuth token endpoint.
    ///    - Success → `authorized`, no browser window.
    ///    - `invalid_grant` → the token is dead: remove it and return
    ///      `needsSignIn` (browser flow).
    ///    - Any other error (network, 5xx) → `failed`, keeping the cached token
    ///      so the user can retry without losing authorization.
    /// 2. No cached token → `needsSignIn`.
    ///
    /// Exchanges the access token via URLSession like every other network call;
    /// the existing code→token exchange in `signIn` is left untouched.
    func ensureAuthorized() async -> AuthCheckResult {
        guard let refreshToken = KeychainTokenStore.refreshToken,
              !refreshToken.isEmpty else {
            print("ℹ️ No cached refresh token — interactive sign-in required")
            return .needsSignIn
        }

        do {
            let newAccessToken = try await exchangeRefreshToken(refreshToken)
            let email = UserDefaults.standard.string(forKey: Self.cachedEmailKey) ?? ""
            let name = UserDefaults.standard.string(forKey: Self.cachedNameKey) ?? ""
            await MainActor.run {
                self.accessToken = newAccessToken
                self.userEmail = email
                self.userName = name
                self.isSignedIn = true
            }
            print("✅ Session restored from cached refresh token")
            return .authorized
        } catch let error as TokenExchangeError {
            switch error {
            case .invalidGrant:
                KeychainTokenStore.deleteRefreshToken()
                print("⚠️ Cached refresh token rejected — interactive sign-in required")
                return .needsSignIn
            case .invalidClient:
                print("⚠️ Token client mismatch — interactive sign-in required")
                return .needsSignIn
            default:
                print("⚠️ Token refresh failed (retry available): \(error.errorDescription ?? "?")")
                return .failed(message: error.errorDescription ?? L.str("auth.check.failed"))
            }
        } catch {
            print("⚠️ Token refresh network error: \(error.localizedDescription)")
            return .failed(message: error.localizedDescription)
        }
    }

    /// Exchanges a refresh token for a fresh access token at
    /// `https://oauth2.googleapis.com/token`.
    private func exchangeRefreshToken(_ refreshToken: String) async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw TokenExchangeError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: ConfigManager.shared.clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        struct TokenResponse: Decodable {
            let access_token: String?
            let error: String?
            let error_description: String?
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw TokenExchangeError.malformedResponse
        }

        if (200..<300).contains(http.statusCode) {
            guard let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data),
                  let accessToken = tokenResponse.access_token, !accessToken.isEmpty else {
                throw TokenExchangeError.malformedResponse
            }
            return accessToken
        }

        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
        let googleError = decoded?.error
        let description = decoded?.error_description ?? "HTTP \(http.statusCode)"

        switch googleError {
        case "invalid_grant":
            throw TokenExchangeError.invalidGrant
        case "invalid_client", "unauthorized_client":
            throw TokenExchangeError.invalidClient
        default:
            if (500..<600).contains(http.statusCode) {
                throw TokenExchangeError.server(message: "OAuth server unavailable (HTTP \(http.statusCode))")
            }
            throw TokenExchangeError.server(message: description)
        }
    }

    /// Refreshes the Google access token in the background, publishing the new
    /// value; returns whether a usable token is available.
    ///
    /// Uses the Google Sign-In SDK when a live session exists, and falls back to
    /// a silent Keychain-based refresh (same token endpoint) otherwise — so the
    /// cached-session path also keeps working after the first token expires.
    func refreshAccessToken() async -> Bool {
        if let user = GIDSignIn.sharedInstance.currentUser {
            return await withCheckedContinuation { continuation in
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

        guard let refreshToken = KeychainTokenStore.refreshToken else { return false }
        do {
            let newAccessToken = try await exchangeRefreshToken(refreshToken)
            await MainActor.run {
                self.accessToken = newAccessToken
                self.isSignedIn = true
            }
            return true
        } catch let error as TokenExchangeError {
            if case .invalidGrant = error {
                KeychainTokenStore.deleteRefreshToken()
            }
            return false
        } catch {
            return false
        }
    }
}
