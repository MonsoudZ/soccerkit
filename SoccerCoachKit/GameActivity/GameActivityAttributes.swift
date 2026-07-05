import ActivityKit
import Foundation

/// Shared Live Activity model for a live match. This file is a member of BOTH
/// the app and the widget-extension targets so the two sides agree on the type.
struct GameActivityAttributes: ActivityAttributes {
    /// The parts of the match that change while it runs.
    public struct ContentState: Codable, Hashable {
        var teamScore: Int
        var opponentScore: Int
        /// e.g. "1st Half", "2nd Quarter", "Overtime".
        var periodLabel: String
        var isRunning: Bool
        /// Anchor for the auto-advancing lock-screen timer: the instant the clock
        /// would have read 0:00. Valid while `isRunning`; the widget renders a
        /// self-updating `Text(timerInterval:)` from it so no per-second pushes
        /// are needed.
        var clockStart: Date
        /// Whole seconds elapsed, used to render a static clock while paused.
        var frozenElapsed: Int
    }

    /// The fixed identity of the match.
    var teamName: String
    var opponentName: String
    /// Team accent as a 24-bit RGB hex string (e.g. "4F46E5") for tinting.
    var accentHex: String
}
