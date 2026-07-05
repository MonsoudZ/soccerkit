import SwiftUI

/// The selectable palette of team accent colors. Stored on `Team.accentName`
/// (the raw value) and resolved case-insensitively with a teal fallback, so
/// existing data and any unknown value degrade gracefully.
enum TeamAccent: String, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, pink, red, orange, green

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }

    static func named(_ name: String) -> TeamAccent {
        TeamAccent(rawValue: name.lowercased()) ?? .teal
    }
}

extension Team {
    var accent: TeamAccent { TeamAccent.named(accentName) }
    var accentColor: Color { accent.color }
}
