import SwiftUI

/// Which single banner the bottom overlay is showing, if any.
///
/// The app has three things it can need to say down there, and they must not
/// stack: a coach holding a phone at the touchline has one glance to give, and
/// two capsules fighting over the same corner is worse than either alone. So
/// this resolves to at most one, in a fixed order of urgency.
enum AppBanner: Equatable {
    /// A delete that can still be taken back. It outranks the warnings because
    /// it is the only one with a deadline — the window shuts in a few seconds
    /// whether or not the coach acts, while a warning is still true afterwards.
    case undo(String)
    /// Changes are only in memory. Outranks a sync failure: sync lag is a
    /// nuisance, an unwritten roster is lost work.
    case saveFailed
    /// The last sync attempt failed, carrying the reason.
    case syncFailed(String)

    /// Picks the banner to show.
    ///
    /// `dismissedSyncMessage` is the sync failure the coach has already waved
    /// away. A *different* failure still gets through, and the caller clears it
    /// once sync stops failing, so a dismissal covers one episode rather than
    /// silencing sync for the rest of the launch.
    static func resolve(
        undoMessage: String?,
        saveStatus: SaveStatus,
        syncStatus: SyncStatus,
        dismissedSyncMessage: String?
    ) -> AppBanner? {
        if let undoMessage { return .undo(undoMessage) }
        if saveStatus == .unsaved { return .saveFailed }
        if case .failed(let message) = syncStatus, message != dismissedSyncMessage {
            return .syncFailed(message)
        }
        return nil
    }

    /// What VoiceOver should say when this banner appears unprompted.
    ///
    /// `nil` for undo: that one is the direct result of a delete the coach just
    /// performed, so it needs no announcement. The warnings arrive on their own
    /// and would otherwise be invisible to anyone who never swipes to the
    /// bottom of the screen.
    var accessibilityAnnouncement: String? {
        switch self {
        case .undo:
            return nil
        case .saveFailed:
            return "\(SaveStatus.unsaved.label). \(SaveStatus.unsaved.bannerMessage)"
        case .syncFailed(let message):
            return "\(SyncStatus.failed(message).label). \(message)"
        }
    }
}

/// A button offered inside a warning banner.
private struct BannerAction {
    let title: String
    let perform: () -> Void
}

/// Owns the bottom banner region for the whole app. Every banner goes through
/// here so there is exactly one thing deciding what occupies that space.
private struct AppBannerModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sync failure the coach dismissed. Cleared as soon as sync stops
    /// failing, so a later failure isn't silently suppressed.
    @State private var dismissedSyncMessage: String?

    private var banner: AppBanner? {
        AppBanner.resolve(
            undoMessage: store.undoMessage,
            saveStatus: store.saveStatus,
            syncStatus: store.syncStatus,
            dismissedSyncMessage: dismissedSyncMessage
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let banner {
                    view(for: banner)
                        // Sliding a warning up from the bottom is motion the
                        // coach didn't ask for; fade it instead when they've
                        // said they don't want that.
                        .transition(reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, Spacing.xl)
                        // Clear the bottom tab bar on iPhone so the banner isn't
                        // obscured by it. The iPad sidebar layout has no tab bar
                        // to clear, and that inset just floats it off the edge.
                        .padding(.bottom, sizeClass == .compact ? 52 : Spacing.xxl)
                }
            }
            .animation(reduceMotion ? nil : Animation.snappy, value: banner)
            .onChange(of: store.syncStatus) {
                if !store.syncStatus.isFailed { dismissedSyncMessage = nil }
            }
            .onChange(of: banner) { _, newValue in
                guard let announcement = newValue?.accessibilityAnnouncement else { return }
                AccessibilityNotification.Announcement(announcement).post()
            }
    }

    @ViewBuilder
    private func view(for banner: AppBanner) -> some View {
        switch banner {
        case .undo(let message):
            undo(message)
        case .saveFailed:
            // Nothing to retry: the write is already re-attempted on the next
            // save and when the app leaves the foreground. The message says
            // what the coach can actually do, which is unlock the device.
            warning(
                systemImage: SaveStatus.unsaved.systemImage,
                tint: SaveStatus.unsaved.tint,
                title: SaveStatus.unsaved.label,
                message: SaveStatus.unsaved.bannerMessage,
                action: nil,
                // Deliberately not dismissible. Letting the coach hide "your
                // changes aren't being saved" invites exactly the quiet data
                // loss this banner exists to prevent, and it clears itself the
                // moment a write succeeds.
                dismiss: nil
            )
        case .syncFailed(let message):
            let status = SyncStatus.failed(message)
            warning(
                systemImage: status.systemImage,
                tint: status.tint,
                title: status.label,
                message: message,
                action: BannerAction(title: "Retry") { store.retrySync() },
                dismiss: { dismissedSyncMessage = message }
            )
        }
    }

    // MARK: - Bodies

    private func undo(_ message: String) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: Spacing.md)
            Button("Undo") { store.undoLastDelete() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        .shadow(color: Elevation.cardColor, radius: Elevation.cardRadius, y: Elevation.cardYOffset)
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            store.dismissUndo()
        }
    }

    private func warning(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        action: BannerAction?,
        dismiss: (() -> Void)?
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
        return HStack(alignment: .top, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // One element rather than three, so VoiceOver reads the warning as
            // a sentence instead of three fragments. The buttons stay siblings
            // and remain separately reachable.
            .accessibilityElement(children: .combine)

            Spacer(minLength: Spacing.md)

            if let action {
                Button(action.title, action: action.perform)
                    .font(.subheadline.weight(.semibold))
            }

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        // The glyph is caption-sized; the thing you tap with a
                        // thumb, on a touchline, shouldn't be.
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.hairline, lineWidth: 0.5))
        .shadow(color: Elevation.cardColor, radius: Elevation.cardRadius, y: Elevation.cardYOffset)
    }
}

extension View {
    /// Overlays the app's bottom banner: an undo offer, or a warning that the
    /// coach's changes aren't reaching disk or the remote.
    func appBanner() -> some View {
        modifier(AppBannerModifier())
    }
}
