import SwiftUI

/// Resumes a continuation exactly once, whichever of the fetch and the spinner
/// cap reaches it first.
///
/// `withCheckedContinuation` traps on a second resume, and both racers are
/// live at once by design: the cap exists precisely for the fetch that never
/// answers, and the fetch that answers late still runs its completion. Both
/// arrive on the main actor, so the single `continuation` reference here is all
/// the mutual exclusion this needs.
@MainActor
final class RefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    /// The spinner cap, cancelled when the fetch wins so it doesn't sit in a
    /// pointless sleep for the rest of its timeout.
    var cap: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        cap?.cancel()
        cap = nil
        continuation?.resume()
        continuation = nil
    }
}

/// Pull-to-refresh that fetches remote changes.
///
/// Attached unconditionally rather than only when sync is on. Adding and
/// removing `.refreshable` would change the view's type, and with it the
/// identity of the scroll view underneath — a coach toggling sync in Settings
/// would come back to a list scrolled to the top. `refreshFromRemote` already
/// declines to do anything when there is no remote to ask, so the gesture is a
/// no-op in that case rather than a lie about what it fetched.
private struct RemoteRefreshModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore

    func body(content: Content) -> some View {
        content.refreshable { await store.refreshFromRemote() }
    }
}

extension View {
    /// Lets the coach pull this list down to fetch remote changes.
    ///
    /// Sync otherwise only fetches at launch and on returning to the
    /// foreground, so the coach whose co-coach just added a fixture had to
    /// background the app and come back to see it.
    func remoteRefreshable() -> some View {
        modifier(RemoteRefreshModifier())
    }
}
