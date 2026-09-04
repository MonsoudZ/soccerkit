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
                if auth.isSignedIn {
                    // A returning coach already has a session; asking iOS for the token
                    // is what completes the pair. Silent — it does not prompt.
                    appDelegate.push.start()
                    appDelegate.push.registerIfPossible()
                }
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
                    // Ask iOS for a device token now; the session it will be registered
                    // against is being fetched on the line above, and whichever lands
                    // second completes the pair.
                    appDelegate.push.start()
                }
            }
        }
    }
}
