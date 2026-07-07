import Foundation

/// Small launch-environment flags. Used to make the app drivable by UI tests
/// (bypass Apple sign-in, skip the notification prompt, skip onboarding) without
/// affecting normal runs.
enum AppEnvironment {
    /// True when launched by the UI test suite (`-uiTesting` launch argument).
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
