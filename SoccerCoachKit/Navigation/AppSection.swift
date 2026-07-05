import Foundation

/// Top-level destinations shown in the sidebar / navigation split view.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case calendar = "Calendar"
    case roster = "Roster"
    case game = "Game Day"
    case games = "Games"
    case stats = "Season"
    case field = "Field"
    case training = "Training"
    case drills = "Drills"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .calendar: return "calendar"
        case .roster: return "person.3"
        case .game: return "stopwatch"
        case .games: return "soccerball"
        case .stats: return "chart.bar.xaxis"
        case .field: return "rectangle.dashed"
        case .training: return "calendar.badge.clock"
        case .drills: return "sportscourt"
        case .settings: return "gearshape"
        }
    }
}
