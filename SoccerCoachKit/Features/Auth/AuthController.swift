import AuthenticationServices
import SwiftUI

/// Owns Sign in with Apple state. The Apple user identifier is stable and not
/// secret, so it's kept in `UserDefaults`; the app has no backend, so this is
/// purely a local identity + gate. On launch the stored credential is
/// re-validated with Apple and cleared if the user revoked access.
@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var displayName: String?
    /// A user-facing message when a sign-in attempt fails (nil = none / cancelled).
    @Published var authError: String?

    var isSignedIn: Bool { userID != nil }

    private let defaults: UserDefaults
    private static let userIDKey = "appleUserID"
    private static let nameKey = "appleUserName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userID = defaults.string(forKey: Self.userIDKey)
        displayName = defaults.string(forKey: Self.nameKey)
    }

    /// Configures the authorization request the Sign in with Apple button makes.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Handles the button's completion, storing the identity on success and
    /// surfacing a message on a genuine failure (user-cancellation is silent).
    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // The full name is only returned on the *first* authorization, so we
            // keep any previously stored name rather than overwriting it with nil.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            authError = nil
            completeSignIn(userID: credential.user, name: name.isEmpty ? nil : name)
        case .failure(let error):
            // Don't nag when the user simply cancelled the sheet.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            authError = "Sign in couldn't be completed. Please try again."
        }
    }

    /// Stores a signed-in identity. Exposed so the flow is testable without a
    /// live `ASAuthorizationAppleIDCredential`.
    func completeSignIn(userID: String, name: String?) {
        self.userID = userID
        defaults.set(userID, forKey: Self.userIDKey)
        if let name, !name.isEmpty {
            displayName = name
            defaults.set(name, forKey: Self.nameKey)
        }
    }

    /// Re-checks the stored Apple credential on launch and signs out if it was
    /// revoked or is no longer found.
    func refreshCredentialState() {
        guard let userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state != .authorized else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    func signOut() {
        userID = nil
        displayName = nil
        defaults.removeObject(forKey: Self.userIDKey)
        defaults.removeObject(forKey: Self.nameKey)
    }
}
