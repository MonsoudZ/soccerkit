import ActivityKit
import Foundation

/// Thin facade over ActivityKit so the rest of the app can drive the Game Day
/// Live Activity without sprinkling availability checks. It no-ops before
/// iOS 16.1 or when the user has disabled Live Activities. `current` is stored
/// as `Any` so this type needn't itself be gated to iOS 16.1.
final class GameActivityController {
    static let shared = GameActivityController()
    private init() {}

    private var current: Any?

    var isActive: Bool { current != nil }

    /// The APNs push token for the running activity, as a hex string. A backend
    /// can push `content-state` updates to this token (e.g. from an in-stadium
    /// scoring service) so the activity updates even when the app isn't running.
    /// `nil` until the system issues a token — which requires the app's Push
    /// Notifications capability; local `update(...)` works regardless.
    private(set) var pushToken: String?

    /// Called whenever the push token changes, so an integration can register it
    /// with a server. Set before starting an activity.
    var onPushTokenChange: ((String) -> Void)?

    /// Called (on the main actor) when the score changes from an interactive
    /// Live Activity button, so the in-app scoreboard can stay in sync.
    var onScoreChange: ((_ team: Int, _ opponent: Int) -> Void)?

    /// Adjusts the live score from a Live Activity button. Resolves the activity
    /// from the running list (so it works even after the app was relaunched in
    /// the background to run the intent), pushes the new state, and notifies the
    /// app.
    func adjustScore(homeDelta: Int, awayDelta: Int) async {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = (current as? Activity<GameActivityAttributes>)
                ?? Activity<GameActivityAttributes>.activities.first else { return }

        var state: GameActivityAttributes.ContentState
        if #available(iOS 16.2, *) { state = activity.content.state } else { state = activity.contentState }
        state.teamScore = max(0, state.teamScore + homeDelta)
        state.opponentScore = max(0, state.opponentScore + awayDelta)

        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: Self.staleAfter()))
        } else {
            await activity.update(using: state)
        }

        let team = state.teamScore, opponent = state.opponentScore
        let callback = onScoreChange
        await MainActor.run { callback?(team, opponent) }
    }

    /// Starts a Live Activity, or updates the existing one if already running.
    func start(teamName: String, opponentName: String, accentHex: String,
               teamScore: Int, opponentScore: Int, periodLabel: String,
               isRunning: Bool, elapsed: Int) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if current != nil {
            update(teamScore: teamScore, opponentScore: opponentScore,
                   periodLabel: periodLabel, isRunning: isRunning, elapsed: elapsed)
            return
        }

        let attributes = GameActivityAttributes(
            teamName: teamName, opponentName: opponentName, accentHex: accentHex
        )
        let state = contentState(teamScore: teamScore, opponentScore: opponentScore,
                                 periodLabel: periodLabel, isRunning: isRunning, elapsed: elapsed)
        do {
            let activity: Activity<GameActivityAttributes>
            // Request with `.token` so the activity is push-updatable; local
            // updates still work if no push token is ever issued.
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: Self.staleAfter()),
                    pushType: .token
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes, contentState: state, pushType: .token
                )
            }
            current = activity
            observePushToken(for: activity)
        } catch {
            current = nil
        }
    }

    /// A running match with no updates for a few hours is almost certainly over,
    /// so content goes stale — a forgotten activity dims and can be reclaimed by
    /// the system instead of lingering on the Lock Screen forever.
    private static func staleAfter() -> Date { Date().addingTimeInterval(3 * 3600) }

    /// Pulls the activity's current score back into the app — e.g. goals tapped
    /// on the Lock Screen while the app was backgrounded or terminated. Call on
    /// foreground, after `onScoreChange` is wired.
    func reconcile() {
        guard #available(iOS 16.1, *),
              let activity = (current as? Activity<GameActivityAttributes>)
                ?? Activity<GameActivityAttributes>.activities.first else { return }
        current = activity
        let state: GameActivityAttributes.ContentState
        if #available(iOS 16.2, *) { state = activity.content.state } else { state = activity.contentState }
        let team = state.teamScore
        let opponent = state.opponentScore
        let callback = onScoreChange
        Task { @MainActor in callback?(team, opponent) }
    }

    /// Streams the activity's push token to `pushToken` / `onPushTokenChange`.
    @available(iOS 16.1, *)
    private func observePushToken(for activity: Activity<GameActivityAttributes>) {
        Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                self?.pushToken = hex
                self?.onPushTokenChange?(hex)
            }
        }
    }

    /// Pushes new dynamic state to the running activity.
    func update(teamScore: Int, opponentScore: Int, periodLabel: String,
                isRunning: Bool, elapsed: Int) {
        guard #available(iOS 16.1, *),
              let activity = current as? Activity<GameActivityAttributes> else { return }
        let state = contentState(teamScore: teamScore, opponentScore: opponentScore,
                                 periodLabel: periodLabel, isRunning: isRunning, elapsed: elapsed)
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: Self.staleAfter()))
            } else {
                await activity.update(using: state)
            }
        }
    }

    /// Ends and dismisses the activity.
    func end() {
        pushToken = nil
        guard #available(iOS 16.2, *),
              let activity = current as? Activity<GameActivityAttributes> else {
            current = nil
            return
        }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    @available(iOS 16.1, *)
    private func contentState(teamScore: Int, opponentScore: Int, periodLabel: String,
                              isRunning: Bool, elapsed: Int) -> GameActivityAttributes.ContentState {
        GameActivityAttributes.ContentState(
            teamScore: teamScore,
            opponentScore: opponentScore,
            periodLabel: periodLabel,
            isRunning: isRunning,
            // Anchor the auto-advancing timer to when the clock read 0:00.
            clockStart: Date().addingTimeInterval(-Double(elapsed)),
            frozenElapsed: elapsed
        )
    }
}
