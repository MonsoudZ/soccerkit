import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The one thing SwiftUI's `App` cannot do for itself: receive the APNs device token.
///
/// `didRegisterForRemoteNotificationsWithDeviceToken` is a `UIApplicationDelegate`
/// callback with no SwiftUI equivalent, so the app adopts a delegate for it and for
/// nothing else. The registrar lives here because the delegate is where the token
/// arrives, and `@UIApplicationDelegateAdaptor` is how the rest of the app reaches it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushRegistrar()

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { push.deviceTokenReceived(deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MainActor.assumeIsolated { push.registrationFailed(error) }
    }
}
