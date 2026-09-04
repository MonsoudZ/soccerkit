# SoccerCoachKit

SoccerCoachKit is a SwiftUI starter app for youth soccer coaches on iPhone and iPad.

The first build focuses on the coach's weekly loop:

- Manage multiple teams and switch between them.
- Save teams, rosters, drills, sessions, attendance, diagrams, and selected team locally between launches.
- Select an age group with default roster limits, game format, and game length.
- Create and edit teams, players, drills, and training sessions.
- View a roster with player numbers, positions, guardians, and coach notes.
- Store parent/guardian contact details, a secondary contact, and an emergency contact with tap-to-call and tap-to-email links.
- Record player allergies and medical notes for quick reference on game day.
- Schedule games with opponent, date, venue, and location.
- Add tournaments, scrimmages, socials, and meetings as team events, including multi-day tournaments with a start and end date.
- See practices, games, and events together on a color-coded month calendar, tap any day for its agenda, and add new items straight to the selected date.
- Collect RSVPs (going/maybe/not going) from the roster for games, training sessions, and team events.
- Manage game-day starters and bench players.
- Start a game clock that tracks each player's playing time.
- Preset substitution reminders, then record the sub when the reminder fires.
- Use quick substitutions, undo the last recorded sub, manage periods/halftime, and mark players late or injured during games.
- Plan training sessions with objectives, timed blocks, and linked drills.
- Track attendance for each player.
- Build persistent field diagrams with team players, opposition markers, coaching zones, and drawn movement lines.
- Attach diagrams to training sessions or keep them as game plans.
- Duplicate diagrams and export/share them as PNG or PDF.
- Browse a drill library by category.
- Sign in with Apple, and sync teams, rosters, and plans across devices through iCloud or the Go backend.
- Pull any list down to fetch remote changes without waiting for the next launch.
- Run pre- and post-match questionnaires, and build reusable evaluation forms for tryouts, development reviews, and coach reviews.
- Read a season summary: record, goals and assists per player, squad availability, and per-player development trends.
- Follow the live match on the Lock Screen and Dynamic Island, and see the next fixture in a Home Screen widget.
- Use adaptive `NavigationSplitView` behavior that feels natural on iPad while still working on iPhone.

The roster holds children's names, medical notes and guardian contacts, so
the saved snapshot is encrypted at rest under a key held in the Keychain. A
write that can't be sealed is dropped rather than written in the clear, and
the app says so rather than losing the change quietly.

## Open It

Open `SoccerCoachKit.xcodeproj` in Xcode and run the `SoccerCoachKit` scheme on an iPhone or iPad simulator.

## Project Structure

The app follows an MVVM + services layout, grouped by feature:

- `App/` — the `@main` entry point.
- `Models/` — one Codable domain type per file (`Team`, `Player`, `Drill`, `TrainingSession`, `GameEvent`, `TeamEvent`, `TacticsDiagram`, and shared enums).
- `Services/` — a `PersistenceService` protocol with a `UserDefaults` implementation, the Codable `AppSnapshot`, and `SampleData` seed content.
- `Store/` — `AppStore`, the app-wide `ObservableObject` source of truth. It exposes published collections and intents, and delegates durability to the persistence service.
- `Features/<Feature>/` — each screen paired with its `ObservableObject` view model (`Dashboard`, `Calendar`, `Roster`, `Games`, `Training`, `GameDay`, `Field`, `Drills`, `Teams`). Views observe the store for reactive data and own a view model for local state and intents.
- `Components/` — reusable views shared across features (rows, cards, badges).
- `Navigation/` — `ContentView` and the `AppSection` sidebar model.
- `Networking/` — the backend API client, the sync service, and Keychain-backed token storage.
- `Forms/` — the evaluation engine: form templates, the runner, and answer migration.
- `DesignSystem/` — spacing, radii, elevation, type, and the themeable palette.
- `Extensions/` — small shared helpers.
- `SoccerCoachKitTests/` — XCTest unit tests (timekeeping, persistence, Codable migration, store intents).

## Development

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonyz/XcodeGen) — treat `project.yml` as the source of truth and regenerate after adding files or changing build settings:

```sh
brew install xcodegen
xcodegen generate
```

### Connecting to the Go backend (local dev)

By default the app is **unconfigured** — `BackendBaseURL` is empty, so it runs on CloudKit + local (and the "inert until configured" tests hold). To point local dev at the [Go backend](https://github.com/MonsoudZ/soccerkit-api), create your own gitignored override — **don't** hardcode a URL in `project.yml`, which would ship the dev host and break CI:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # gitignored; per-machine
xcodegen generate
```

`Config/Local.xcconfig` sets `BACKEND_BASE_URL` per SDK — simulator → `http://127.0.0.1:3000/api`, device → the Mac's bonjour name / LAN IP. Because it's gitignored, it never ships and never collides between machines or sessions.

### Push notifications

When a backend is configured, the app registers this device for remote notifications and
hands the APNs token to `POST /v1/me/devices`; sign-out calls `DELETE /v1/me/devices/{token}`
so the server stops pushing to a phone that is no longer this coach's. The backend uses it
today for one thing: telling someone they have been invited to a club, which is the one
event they cannot discover from their own device.

A device token and a backend session arrive from different places and in either order, so
neither registers on its own — `PushRegistrar` keeps whichever it has and completes the
pair when the other lands. The token is remembered across launches, because iOS often
issues it long before a returning coach's session is confirmed.

Two things to know:

- **Two separate things.** `registerForRemoteNotifications()` is silent and decides
  whether a push can be *sent*; notification authorization decides whether it is *shown*.
  The permission prompt is asked at sign-in, because the alternatives — the reminders
  toggle and game day — are reached only by a coach who already wanted something else,
  and an invitation is exactly what a coach who wanted neither cannot otherwise find out
  about. Those two call sites remain, and now re-read the answer rather than asking
  again.
- **The simulator cannot receive real pushes.** It has no APNs token, so `didRegister…`
  never fires there and nothing is registered. Test on a device, with the backend's
  `APNS_*` values set and `APNS_PRODUCTION` matching how the app was built — a sandbox
  build's token is rejected by production and vice versa.

Run the tests from the command line:

```sh
xcodebuild test -scheme SoccerCoachKit -destination 'platform=iOS Simulator,name=iPhone 17'
```

Simulator names drift with each Xcode release, so a pinned one goes stale
rather than failing usefully — `xcrun simctl list devices available` says what
this machine actually has. CI doesn't pin at all; it picks a device by UDID.

Every push and pull request builds the app and runs the test suite via GitHub Actions (`.github/workflows/ci.yml`).

## Good Next Features

The four that used to be listed here — CloudKit sync, local reminders,
exportable session plans, and player development ratings — have all shipped.

- Role-based sharing, so a director sees their coaches' teams and a parent
  sees only their own child. This is the one the backend exists for; the
  client models it already (`Permissions.swift`, `ShareGrant`) and the server
  is the authority. See `docs/backend-architecture.md`.
- Reading the evaluation forms back as trends across a squad, not just per
  player: "poor sleep, poor game" is the question the normalized answer rows
  were shaped to answer.
- Offline queueing for pushes, so edits made on a touchline with no signal
  leave the device as soon as there is one.
