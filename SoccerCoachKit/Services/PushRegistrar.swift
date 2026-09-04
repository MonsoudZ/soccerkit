import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Keeps the backend told where to reach this coach.
///
/// The app has always scheduled *local* notifications — fixtures, substitutions — and
/// never registered for remote ones. That was fine while everything worth saying was
/// something the app already knew. An invitation to join a club is not: it is written by
/// someone else, on another device, and until the coach happens to open the app and look
/// at their invitations they have no idea it exists.
///
/// Two things have to line up before this device can be registered, and they arrive in
/// either order: APNs hands over a device token some time after
/// `registerForRemoteNotifications()`, and the backend session appears some time after
/// Sign in with Apple. So neither arrival registers on its own — each stores what it has
/// and asks whether the other is ready.
///
/// Inert unless a backend is configured, like the rest of this layer: a CloudKit-only
/// build has no server to tell and never asks iOS for a token.
@MainActor
final class PushRegistrar {
    /// Builds a client bound to a specific bearer token. Injected so the tests can
    /// point it at a stubbed session, and so sign-out can hand it a token that is about
    /// to be deleted.
    typealias ClientFactory = (@escaping () -> String?) -> APIClient?

    private let makeClient: ClientFactory
    private let sessionToken: () -> String?
    private let defaults: UserDefaults
    private let isConfigured: () -> Bool

    /// The last (device token, session token) pair successfully registered, so the
    /// several things that can trigger a registration do not each re-send it. The
    /// backend is idempotent, so this is about noise rather than correctness.
    private var lastRegistered: String?

    private static let deviceTokenKey = "apnsDeviceToken"

    init(makeClient: @escaping ClientFactory = { APIClient(tokenProvider: $0) },
         sessionToken: @escaping () -> String? = { TokenStore().token },
         defaults: UserDefaults = .standard,
         isConfigured: @escaping () -> Bool = { BackendConfig.isConfigured }) {
        self.makeClient = makeClient
        self.sessionToken = sessionToken
        self.defaults = defaults
        self.isConfigured = isConfigured
    }

    /// The APNs token for this install, remembered across launches.
    ///
    /// Persisted because the two halves can arrive an app launch apart: iOS often hands
    /// the token over long before a returning coach's session is confirmed, and a coach
    /// who signs in on a later launch would otherwise wait for the next token issue to
    /// be reachable.
    private(set) var deviceToken: String? {
        get { defaults.string(forKey: Self.deviceTokenKey) }
        set { defaults.set(newValue, forKey: Self.deviceTokenKey) }
    }

    /// Asks iOS for a device token. Safe to call repeatedly — the answer arrives at
    /// `deviceTokenReceived` either way, and iOS reissues the same token for the same
    /// install.
    ///
    /// This does not prompt. `registerForRemoteNotifications()` is silent; what governs
    /// whether a push is *displayed* is the notification authorization the app already
    /// asks for when reminders are switched on. So a coach who has never enabled
    /// reminders will be registered and still see nothing — see the note in the README.
    func start() {
        guard isConfigured() else { return }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// APNs handed over a token. Stored, then registered if there is a session to
    /// register it against.
    func deviceTokenReceived(_ raw: Data) {
        deviceToken = Self.hex(raw)
        registerIfPossible()
    }

    /// APNs refused. Nothing to retry here — iOS decides when to try again — but a
    /// silent failure would leave "invitations never notify me" with no thread to pull.
    func registrationFailed(_ error: Error) {
        NSLog("push: iOS would not issue a device token: \(error.localizedDescription)")
    }

    /// Registers when both halves are in hand. Called on token arrival and again once a
    /// backend session exists, because either may be the one that completes the pair.
    func registerIfPossible() {
        guard isConfigured(), let token = deviceToken, let session = sessionToken() else { return }
        let pair = token + "|" + session
        guard pair != lastRegistered else { return }
        guard let client = makeClient({ session }) else { return }
        lastRegistered = pair
        Task {
            do {
                try await client.registerDevice(token: token)
            } catch {
                // Best effort by design. Failing to register costs a notification, not
                // the invitation itself, which /me/invitations still carries.
                lastRegistered = nil
                NSLog("push: registering this device failed: \(error)")
            }
        }
    }

    /// Tells the backend to stop pushing here, and must be called *before* the session
    /// is cleared.
    ///
    /// The request is authenticated by the very token sign-out is about to delete, so
    /// the token is captured now and handed to the client explicitly rather than read
    /// from storage inside the task — by the time that ran, there would be nothing to
    /// read and the call would go out unauthenticated.
    func unregisterCurrentDevice() {
        lastRegistered = nil
        guard isConfigured(), let token = deviceToken, let session = sessionToken(),
              let client = makeClient({ session })
        else { return }
        Task {
            do {
                try await client.unregisterDevice(token: token)
            } catch {
                // The server prunes a token Apple rejects, so a missed unregister
                // resolves itself the first time it pushes to a device that has signed
                // out. Worth a line, not worth blocking sign-out.
                NSLog("push: unregistering this device failed: \(error)")
            }
        }
    }

    /// APNs tokens are bytes; the wire format on both sides is lower-case hex, which is
    /// also what the backend validates.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
