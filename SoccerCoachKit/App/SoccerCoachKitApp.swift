import SwiftUI

@main
struct SoccerCoachKitApp: App {
    @StateObject private var store = AppStore.storedOrSample
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var auth = AuthController()
    @StateObject private var tabPreferences = TabPreferences()
    /// Adopted for one callback SwiftUI does not surface: the APNs device token.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if AppEnvironment.isUITesting {
            // Skip the first-run cover so UI tests land on the main UI.
            UserDefaults.standard.set(true, forKey: "hasOnboarded")
        }
    }

    /// What a signed-in coach needs set up, at launch and at sign-in alike.
    ///
    /// Notification permission is asked for here — see `AppStore.coachDidSignIn` for why
    /// it moved off the reminders toggle. Then iOS is asked for a device token, which is
    /// silent and separate: permission decides whether a push is *shown*, the token
    /// decides whether one can be *sent*. A returning coach already has a session, so
    /// registering may complete immediately; a fresh sign-in is still fetching one, and
    /// whichever of the two lands second completes the pair.
    @MainActor
    private func prepareSignedInCoach() {
        store.coachDidSignIn()
        appDelegate.push.start()
        appDelegate.push.registerIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn || AppEnvironment.isUITesting {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(store)
            .environmentObject(themeManager)
            .environmentObject(auth)
            .environmentObject(tabPreferences)
            .environment(\.theme, themeManager.current)
            .tint(themeManager.current.brand)
            .task {
                auth.refreshCredentialState()
                // Both halves of push registration, joined here because this is the one
                // place that holds the delegate, the store and the auth controller.
                store.onBackendSession = { [push = appDelegate.push] in push.registerIfPossible() }
                auth.willSignOut = { [push = appDelegate.push] in push.unregisterCurrentDevice() }
                if auth.isSignedIn { prepareSignedInCoach() }
            }
            .onChange(of: auth.userID) {
                // Load the newly-signed-in coach's data (and stash the previous
                // coach's), so accounts never see each other's data.
                store.switchUser(to: auth.userID)
                // Establish the coach as owner of their personal org: a Person,
                // a linked UserAccount, and an admin+director+coach membership.
                if let userID = auth.userID {
                    store.ensureOwner(appleUserID: userID, displayName: auth.displayName)
                    // Exchange the fresh Apple identity token for a backend
                    // session token, then (re)start authenticated sync.
                    store.authenticateBackend(
                        identityToken: auth.identityToken,
                        authorizationCode: auth.authorizationCode,
                        fullName: auth.displayName
                    )
                    prepareSignedInCoach()
                }
            }
        }
    }
}
