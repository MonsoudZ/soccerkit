import SwiftUI

@main
struct SoccerCoachKitApp: App {
    @StateObject private var store = AppStore.storedOrSample
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var auth = AuthController()
    @StateObject private var tabPreferences = TabPreferences()

    init() {
        if AppEnvironment.isUITesting {
            // Skip the first-run cover so UI tests land on the main UI.
            UserDefaults.standard.set(true, forKey: "hasOnboarded")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.hasAccess || AppEnvironment.isUITesting {
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
            .task { auth.refreshCredentialState() }
            .onChange(of: auth.userID) {
                // Load the newly-signed-in coach's data (and stash the previous
                // coach's), so accounts never see each other's data.
                // `upgradedFromGuest` distinguishes a guest getting an account
                // (their roster follows them) from a second coach signing in on a
                // shared device (it must not).
                store.switchUser(to: auth.userID, carryingLocalData: auth.upgradedFromGuest)
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
                }
            }
        }
    }
}
