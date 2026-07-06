import SwiftUI

@main
struct SoccerCoachKitApp: App {
    @StateObject private var store = AppStore.storedOrSample
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var auth = AuthController()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(store)
            .environmentObject(themeManager)
            .environmentObject(auth)
            .environment(\.theme, themeManager.current)
            .tint(themeManager.current.brand)
            .task { auth.refreshCredentialState() }
            .onChange(of: auth.userID) { _ in
                // Load the newly-signed-in coach's data (and stash the previous
                // coach's), so accounts never see each other's data.
                store.switchUser(to: auth.userID)
            }
        }
    }
}
