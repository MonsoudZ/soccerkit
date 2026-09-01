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

    var isSignedIn: Bool { userID != nil }

    private let defaults: UserDefaults
    /// The backend session this identity owns, cleared on sign-out.
    private let tokens: TokenStore
    private static let userIDKey = "appleUserID"
    private static let nameKey = "appleUserName"

    init(defaults: UserDefaults = .standard, tokens: TokenStore = TokenStore()) {
        self.defaults = defaults
        self.tokens = tokens
        userID = defaults.string(forKey: Self.userIDKey)
        displayName = defaults.string(forKey: Self.nameKey)
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
        defaults.set(userID, forKey: Self.userIDKey)
        if let name, !name.isEmpty {
            displayName = name
            defaults.set(name, forKey: Self.nameKey)
        }
    }

    /// Whether a credential-state check means the coach's Apple session is over.
    ///
    /// Only a credential that is definitively gone ends the session. This used to
    /// be `state != .authorized`, which swept up two cases it shouldn't:
    ///
    /// - A check that *failed*. The error was discarded, and a failed check
    ///   reports `.notFound` — indistinguishable, from the state alone, from a
    ///   credential the user actually deleted. So a transient failure signed the
    ///   coach out.
    /// - `.transferred`, which means the app moved to a different developer team.
    ///   The coach is still signed in; the account just needs migrating.
    ///
    /// This runs on every launch, and signing out is expensive: it drops the
    /// coach into the guest namespace — an app that looks empty, because their
    /// data lives under their own partition — and clears the backend session, so
    /// getting back needs a full Sign in with Apple round-trip. Staying signed in
    /// on an inconclusive answer costs nothing by comparison; the next launch
    /// checks again.
    /// `nonisolated` because the credential-state completion runs off the main
    /// actor; the decision is pure, so it needs no isolation.
    nonisolated static func shouldSignOut(state: ASAuthorizationAppleIDProvider.CredentialState,
                                          error: Error?) -> Bool {
        guard error == nil else { return false }
        switch state {
        case .revoked, .notFound: return true
        case .authorized, .transferred: return false
        @unknown default: return false // a state we don't understand is not proof
        }
    }

    /// Re-checks the stored Apple credential on launch and signs out only if it
    /// was revoked or is genuinely no longer there.
    func refreshCredentialState() {
        guard let userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, error in
            guard Self.shouldSignOut(state: state, error: error) else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    /// Ends the session. The backend tokens go with it: they are this coach's
    /// bearer credentials, so leaving them in the Keychain would let sync keep
    /// talking to the server as them — pushing the signed-out guest namespace's
    /// edits under their identity, and, if a different coach signs in on this
    /// device, syncing as the previous one until (or unless) the new handshake
    /// succeeds.
    func signOut() {
        userID = nil
        displayName = nil
        identityToken = nil
        authorizationCode = nil
        defaults.removeObject(forKey: Self.userIDKey)
        defaults.removeObject(forKey: Self.nameKey)
        tokens.clear()
    }
}
