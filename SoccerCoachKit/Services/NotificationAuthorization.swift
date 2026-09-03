import Foundation
import UserNotifications

/// Whether a reminder the coach set up will actually reach them.
///
/// The app schedules local notifications for upcoming fixtures and for
/// substitutions, and it asked for permission and then discarded the answer:
/// "a denial degrades gracefully — nothing fires" was written down as the
/// intended behaviour. Nothing firing is the whole problem. A coach who turned
/// Event Reminders on, chose an hour's notice, and was never told the app
/// couldn't deliver has been quietly relying on a feature that isn't running.
enum NotificationAuthorization: Equatable {
    /// Permission hasn't been asked for yet.
    case notDetermined
    /// Notifications will be delivered and will interrupt.
    case authorized
    /// Permitted, but they'll land silently in Notification Center — either
    /// provisional authorization or banners switched off. That's no use for a
    /// substitution due in ninety seconds.
    case quiet
    case denied

    init(_ settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .provisional:
            self = .quiet
        // `.ephemeral` is the App Clip grant, which delivers normally.
        case .authorized, .ephemeral:
            // Granted but with alerts switched off delivers to Notification
            // Center and nowhere else, which for a timed reminder is the same
            // outcome as a denial arriving politely.
            self = settings.alertSetting == .disabled ? .quiet : .authorized
        @unknown default:
            self = .notDetermined
        }
    }

    /// What to tell the coach about reminders they've set up, or `nil` when
    /// there's nothing to say.
    ///
    /// Silent while permission hasn't been asked for: the app asks the moment
    /// reminders are switched on, and warning about a dialog that hasn't been
    /// shown yet is warning about nothing.
    var reminderWarning: String? {
        switch self {
        case .notDetermined, .authorized:
            return nil
        case .quiet:
            return "Notification banners are off for SoccerCoachKit, so these reminders will arrive silently in Notification Center."
        case .denied:
            return "Notifications are off for SoccerCoachKit, so these reminders won't arrive at all."
        }
    }

    /// Whether iOS Settings is where the coach has to go to fix this.
    var isFixableInSettings: Bool { reminderWarning != nil }
}
