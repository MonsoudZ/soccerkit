import SwiftUI

@main
struct SoccerCoachKitApp: App {
    @StateObject private var store = AppStore.storedOrSample
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(themeManager)
                .environment(\.theme, themeManager.current)
                .tint(themeManager.current.brand)
        }
    }
}
