import AuthenticationServices
import SwiftUI

/// Owns Sign in with Apple state. The Apple user identifier is stable and not
/// secret, so it's kept in `UserDefaults`. When a backend is configured, the
/// captured identity token is handed to `AppStore.authenticateBackend` for the
/// session exchange; otherwise it's a local identity gate. On launch the stored
/// credential is re-validated with Apple and cleared if the user revoked access.
@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var displayName: String?
    /// The Apple identity token (a JWT) from the most recent sign-in, to hand to
    /// the backend at `/v1/auth/apple` for verification. Not persisted — Apple
    /// re-issues it on each sign-in, so it's only valid right after `handle`.
    @Published private(set) var identityToken: String?
    /// The one-time authorization code from the most recent sign-in.
    @Published private(set) var authorizationCode: String?
    /// A user-facing message when a sign-in attempt fails (nil = none / cancelled).
    @Published var authError: String?

    /// Whether the coach chose to use the app without an account.
    ///
    /// Sign in with Apple is how data follows a coach between devices, but it is
    /// not what makes the app useful — a coach on a touchline wanting to track
    /// minutes should not be stopped by an account wall, and the App Store
    /// guidelines don't allow requiring one for functionality that doesn't need
    /// it. Persisted, so the wall doesn't reappear on the next launch.
    @Published private(set) var isGuest: Bool

    var isSignedIn: Bool { userID != nil }
    /// Whether the app should be usable at all: signed in, or deliberately not.
    var hasAccess: Bool { isSignedIn || isGuest }

    /// Whether the most recent sign-in upgraded a guest session. Read by the app
    /// when it hands the change to `AppStore.switchUser`, which cannot tell an
    /// upgrade from a second coach signing in on a shared device.
    private(set) var upgradedFromGuest = false

    private let defaults: UserDefaults
    private static let userIDKey = "appleUserID"
    private static let nameKey = "appleUserName"
    private static let guestKey = "continuedAsGuest"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userID = defaults.string(forKey: Self.userIDKey)
        displayName = defaults.string(forKey: Self.nameKey)
        isGuest = defaults.bool(forKey: Self.guestKey)
    }

    /// Takes the coach past the sign-in gate without an account. Their work is
    /// kept in the signed-out partition and follows them into their account if
    /// they sign in later (see `AppStore.switchUser`).
    func continueAsGuest() {
        guard !isSignedIn else { return }
        isGuest = true
        defaults.set(true, forKey: Self.guestKey)
    }

    /// Configures the authorization request the Sign in with Apple button makes.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
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
            // Capture the tokens for the backend handshake (verified server-side).
            identityToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
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
        upgradedFromGuest = isGuest
        // No longer a guest: they have an account, so signing out should return
        // them to the gate rather than silently back into the guest partition.
        isGuest = false
        defaults.removeObject(forKey: Self.guestKey)
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
        isGuest = false
        upgradedFromGuest = false
        defaults.removeObject(forKey: Self.userIDKey)
        defaults.removeObject(forKey: Self.nameKey)
        defaults.removeObject(forKey: Self.guestKey)
    }
}
