import Foundation

/// Small launch-environment flags. Used to make the app drivable by UI tests
/// (bypass Apple sign-in, skip the notification prompt, skip onboarding) without
/// affecting normal runs.
enum AppEnvironment {
    /// True when launched by the UI test suite (`-uiTesting` launch argument).
    /// This is the *app under test* — a separate process the UI runner launches.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// True when this process is hosting an XCTest bundle — i.e. the app's
    /// `@main` is running as the unit-test host. Xcode sets
    /// `XCTestConfigurationFilePath` in that process's environment. The host
    /// still runs `storedOrSample` on launch, so it must skip entitlement-gated
    /// services (CloudKit) that the unsigned CI test host can't use.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Either test context: the app should avoid launch-time CloudKit.
    static var isTestingOrUITesting: Bool { isUITesting || isRunningTests }
}
