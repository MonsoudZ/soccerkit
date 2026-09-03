import SwiftUI

/// Maps what the coach just did to what the phone should do about it.
///
/// Game day is the one screen used without looking at it: the coach is watching
/// the pitch, and the phone is confirming that the tap landed. That's what
/// these are for, which is also why they're sparing — a buzz for every tap
/// stops meaning anything.
enum MatchFeedback {
    static func feedback(for kind: MatchEvent.Kind) -> SensoryFeedback {
        switch kind {
        case .clockStarted: return .start
        case .clockPaused: return .stop
        // The heaviest of the set: a period boundary is the one moment here
        // that changes what every other control means.
        case .periodAdvanced: return .impact(weight: .heavy)
        case .subRecorded: return .success
        // Softer than the sub it takes back, so the two are told apart by feel
        // rather than only by looking.
        case .subUndone: return .impact(flexibility: .soft)
        case .goalFor: return .success
        // Not `.error`: the opposition scoring is a fact to record, not a
        // mistake the coach made.
        case .goalAgainst: return .impact(weight: .medium)
        case .scoreCorrected: return .impact(flexibility: .soft)
        // The one that arrives unbidden, so it's the one that has to feel
        // different from a tap being acknowledged.
        case .reminderDue: return .warning
        }
    }
}

private struct MatchFeedbackModifier: ViewModifier {
    let event: MatchEvent?

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: event) { _, new in
            new.map { MatchFeedback.feedback(for: $0.kind) }
        }
    }
}

extension View {
    /// Plays haptic feedback for match actions as they happen.
    ///
    /// Driven by `MatchEvent` rather than by the match's state, so reopening a
    /// saved match doesn't replay its goals into the coach's hand.
    func matchFeedback(_ event: MatchEvent?) -> some View {
        modifier(MatchFeedbackModifier(event: event))
    }
}

/// Whether the phone should be stopped from locking itself.
enum ScreenWake {
    /// Awake while the match clock is actually running, and only then.
    ///
    /// A coach on the touchline glances at the clock every few minutes without
    /// touching the phone, and a screen that locks between glances costs them a
    /// Face ID unlock in the middle of a substitution. A *paused* clock earns
    /// nothing: half time, or a match sitting between periods, should let the
    /// phone sleep like anything else — and so should a backgrounded app, where
    /// the Live Activity is showing the clock on the lock screen anyway.
    static func shouldStayAwake(clockRunning: Bool, phase: ScenePhase) -> Bool {
        clockRunning && phase == .active
    }
}

private struct MatchScreenWakeModifier: ViewModifier {
    @ObservedObject var match: GameDayViewModel
    @Environment(\.scenePhase) private var phase

    private var isAwake: Bool {
        ScreenWake.shouldStayAwake(clockRunning: match.isRunning, phase: phase)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isAwake, initial: true) {
                UIApplication.shared.isIdleTimerDisabled = isAwake
            }
            // Belt and braces. iOS clears the idle timer for an app that isn't
            // frontmost, but this flag is global to the process and leaving it
            // set on the way out would be a battery leak nothing else clears.
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    /// Stops the phone locking itself while `match`'s clock is running.
    ///
    /// Takes the view model rather than a `Bool` the caller computed.
    /// `AppStore.gameDay` is a nested `ObservableObject`, so a view observing
    /// only the store is never told that the clock started or stopped — the
    /// screen would then follow whatever else happened to redraw that view.
    /// Observing it here is what makes the flag track the clock.
    func keepScreenAwake(during match: GameDayViewModel) -> some View {
        modifier(MatchScreenWakeModifier(match: match))
    }
}
