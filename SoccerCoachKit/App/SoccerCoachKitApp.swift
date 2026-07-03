import SwiftUI

@main
struct SoccerCoachKitApp: App {
    @StateObject private var store = AppStore.storedOrSample

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
