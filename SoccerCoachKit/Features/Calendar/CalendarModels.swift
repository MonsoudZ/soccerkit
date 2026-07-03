import SwiftUI

/// A single kind of thing that can appear on the coach's calendar. This unifies
/// training sessions, games, and general team events (tournaments, socials, ...)
/// into one colour-coded vocabulary for the calendar UI.
enum CalendarEventKind: Hashable {
    case practice
    case game
    case tournament
    case scrimmage
    case social
    case meeting
    case other

    init(_ eventKind: TeamEventKind) {
        switch eventKind {
        case .tournament: self = .tournament
        case .scrimmage: self = .scrimmage
        case .social: self = .social
        case .meeting: self = .meeting
        case .other: self = .other
        }
    }

    var label: String {
        switch self {
        case .practice: return "Practice"
        case .game: return "Game"
        case .tournament: return "Tournament"
        case .scrimmage: return "Scrimmage"
        case .social: return "Team Event"
        case .meeting: return "Meeting"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .practice: return "figure.run"
        case .game: return "soccerball"
        case .tournament: return "trophy"
        case .scrimmage: return "sportscourt"
        case .social: return "party.popper"
        case .meeting: return "person.2.wave.2"
        case .other: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .practice: return .teal
        case .game: return .blue
        case .tournament: return .orange
        case .scrimmage: return .green
        case .social: return .pink
        case .meeting: return .indigo
        case .other: return .gray
        }
    }
}

/// A read-only projection of a session/game/event used purely for rendering the
/// calendar. The `reference` lets the agenda navigate to the real detail screen.
struct CalendarItem: Identifiable {
    enum Reference: Hashable {
        case session(UUID)
        case game(UUID)
        case event(UUID)
    }

    let id: UUID
    let date: Date
    let endDate: Date?
    let title: String
    let subtitle: String
    let location: String
    let kind: CalendarEventKind
    let reference: Reference

    var isMultiDay: Bool {
        guard let endDate else { return false }
        return Calendar.current.startOfDay(for: endDate) > Calendar.current.startOfDay(for: date)
    }

    /// True when `day` falls on or between the item's start and end day.
    func covers(_ day: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate ?? date)
        return target >= start && target <= end
    }
}

extension AppStore {
    /// Every schedule item for the selected team, sorted by start time.
    var calendarItems: [CalendarItem] {
        let practices = teamSessions.map { session in
            CalendarItem(
                id: session.id,
                date: session.date,
                endDate: nil,
                title: session.title,
                subtitle: "Practice",
                location: "",
                kind: .practice,
                reference: .session(session.id)
            )
        }

        let matches = teamGames.map { game in
            CalendarItem(
                id: game.id,
                date: game.date,
                endDate: nil,
                title: "vs \(game.opponent)",
                subtitle: game.isHome ? "Home Game" : "Away Game",
                location: game.location,
                kind: .game,
                reference: .game(game.id)
            )
        }

        let others = teamEvents.map { event in
            CalendarItem(
                id: event.id,
                date: event.date,
                endDate: event.endDate,
                title: event.title,
                subtitle: event.kind.rawValue,
                location: event.location,
                kind: CalendarEventKind(event.kind),
                reference: .event(event.id)
            )
        }

        return (practices + matches + others).sorted { $0.date < $1.date }
    }
}
