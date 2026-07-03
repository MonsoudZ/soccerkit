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
- Collect RSVPs (going/maybe/not going) from the roster for both games and training sessions.
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

## Good Next Features

- SwiftData or CloudKit migration for richer sync and sharing.
- Season calendar combining matches and training in one timeline.
- Push/local reminders for upcoming games and RSVP deadlines.
- Exportable full session plans for assistant coaches.
- Player development notes and skill ratings.
