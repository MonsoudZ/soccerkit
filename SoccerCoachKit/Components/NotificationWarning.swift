import SwiftUI

/// Tells the coach that reminders they've set up won't reach them, and offers
/// the one place that can be fixed.
///
/// Used on both screens that schedule notifications. Permission is granted to
/// the app rather than to a feature, so Settings and Game Day are talking about
/// the same switch and should say the same thing about it.
struct NotificationWarningView: View {
    let status: NotificationAuthorization

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message = status.reminderWarning {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(status == .denied ? "Reminders Won't Arrive" : "Reminders Will Be Silent",
                      systemImage: "bell.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.caution)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Only iOS Settings can grant this back, and a coach who has to
                // go hunting for the row usually doesn't.
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .contain)
        }
    }
}
