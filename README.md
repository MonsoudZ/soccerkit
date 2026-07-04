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
- Use adaptive `NavigationSplitView` behavior that feels natural on iPad while still working on iPhone.

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
- `Extensions/` — small shared helpers.
- `SoccerCoachKitTests/` — XCTest unit tests (timekeeping, persistence, Codable migration, store intents).

## Development

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonyz/XcodeGen) — treat `project.yml` as the source of truth and regenerate after adding files or changing build settings:

```sh
brew install xcodegen
xcodegen generate
```

Run the tests from the command line:

```sh
xcodebuild test -scheme SoccerCoachKit -destination 'platform=iOS Simulator,name=iPhone 15'
```

Every push and pull request builds the app and runs the test suite via GitHub Actions (`.github/workflows/ci.yml`).

## Good Next Features

- SwiftData or CloudKit migration for richer sync and sharing.
- Push/local reminders for upcoming games and RSVP deadlines.
- Exportable full session plans for assistant coaches.
- Player development notes and skill ratings.
