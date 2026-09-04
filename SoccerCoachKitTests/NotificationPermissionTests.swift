import XCTest
@testable import SoccerCoachKit

/// The app asked for notification permission and threw the answer away —
/// "a denial degrades gracefully (nothing fires)" was written down as the
/// intended behaviour. A coach could switch Event Reminders on, choose an
/// hour's notice, and be relying on a feature that was never going to run.
@MainActor
final class NotificationPermissionTests: XCTestCase {

    // MARK: - What gets said

    func testAGrantSaysNothing() {
        XCTAssertNil(NotificationAuthorization.authorized.reminderWarning)
    }

    /// The app prompts the moment reminders are switched on, so warning before
    /// the dialog has been answered is warning about nothing.
    func testAnUnansweredPromptSaysNothing() {
        XCTAssertNil(NotificationAuthorization.notDetermined.reminderWarning)
    }

    func testADenialSaysTheRemindersWontArrive() throws {
        let message = try XCTUnwrap(NotificationAuthorization.denied.reminderWarning)

        XCTAssertTrue(message.contains("won't arrive"))
        XCTAssertTrue(NotificationAuthorization.denied.isFixableInSettings)
    }

    /// Granted-but-silent is its own outcome, not a success: a substitution due
    /// in ninety seconds that lands quietly in Notification Center is no more
    /// use than one that never arrives.
    func testSilentDeliveryIsWarnedAboutSeparately() throws {
        let message = try XCTUnwrap(NotificationAuthorization.quiet.reminderWarning)

        XCTAssertTrue(message.contains("silently"))
        XCTAssertNotEqual(message, NotificationAuthorization.denied.reminderWarning,
                          "the two failures need different advice")
    }

    // MARK: - What the store publishes

    private func makeStore(_ center: FakeNotificationCenter)
        -> AppStore {
        AppStore(snapshot: TestData.snapshot(playerCount: 1),
                 persistence: InMemoryPersistence(),
                 scheduleNotifier: ScheduleNotifier(center: center))
    }

    func testTurningRemindersOnRecordsTheAnswer() async {
        let center = FakeNotificationCenter()
        center.authorization = .denied
        let store = makeStore(center)

        store.eventRemindersEnabled = true
        await settle()

        XCTAssertEqual(center.authorizationRequests, 1, "the coach is asked when they opt in")
        XCTAssertEqual(store.notificationStatus, .denied)
        XCTAssertNotNil(store.notificationStatus.reminderWarning)
    }

    /// Permission can be withdrawn in iOS Settings long after it was granted,
    /// and the app is never told. Re-reading on every foreground — the return
    /// trip from that very screen — is what catches it.
    func testStatusIsReReadRatherThanRemembered() async {
        let center = FakeNotificationCenter()
        center.authorization = .authorized
        let store = makeStore(center)
        store.eventRemindersEnabled = true
        await settle()
        XCTAssertNil(store.notificationStatus.reminderWarning)

        // The coach switches notifications off in iOS Settings and comes back.
        center.authorization = .denied
        store.refreshNotificationStatus()
        await settle()

        XCTAssertEqual(store.notificationStatus, .denied)
        XCTAssertEqual(center.authorizationRequests, 1,
                       "re-reading the status must not re-prompt")
    }

    /// Permission belongs to the app, not to a feature. Game day prompting and
    /// Settings prompting have to land on one answer, or the two screens can
    /// disagree about the same switch.
    func testGameDayAndSettingsShareOneAnswer() async {
        let center = FakeNotificationCenter()
        center.authorization = .quiet
        let store = makeStore(center)

        store.requestNotificationPermission()
        await settle()

        XCTAssertEqual(store.notificationStatus, .quiet)
    }

    /// The prompt moved to sign-in. Reminders and game day are both reached only by a
    /// coach who already wanted something else, so a coach who wanted neither was never
    /// asked — and an invitation, which arrives from another device, is exactly the thing
    /// such a coach cannot find out about any other way.
    func testSigningInAsksForPermission() async {
        let center = FakeNotificationCenter()
        center.authorization = .authorized
        let store = makeStore(center)

        store.coachDidSignIn()
        await settle()

        XCTAssertEqual(center.authorizationRequests, 1, "signing in is where the coach is asked")
        XCTAssertEqual(store.notificationStatus, .authorized)
    }

    /// iOS prompts once, so the older call sites must not ask again — they now find the
    /// answer determined and republish it. A second dialog would be a bug the simulator
    /// hides, since it only ever shows the first.
    func testTheOlderPromptsDoNotAskASecondTime() async {
        let center = FakeNotificationCenter()
        center.authorization = .denied
        let store = makeStore(center)

        store.coachDidSignIn()
        await settle()
        store.eventRemindersEnabled = true      // the Settings toggle
        await settle()
        store.requestNotificationPermission()   // game day
        await settle()

        XCTAssertEqual(center.authorizationRequests, 1,
                       "the coach is asked once, at sign-in")
        XCTAssertEqual(store.notificationStatus, .denied,
                       "and the answer still reaches the screens that warn about it")
    }

    /// Lets the store's detached permission Task run to completion.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }
}
