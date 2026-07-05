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

    /// 24-bit RGB hex (approximating the system color) for contexts that can't
    /// use `Color` directly, e.g. the Live Activity widget.
    var hex: String {
        switch self {
        case .teal: return "30B0C7"
        case .blue: return "007AFF"
        case .indigo: return "5856D6"
        case .purple: return "AF52DE"
        case .pink: return "FF2D55"
        case .red: return "FF3B30"
        case .orange: return "FF9500"
        case .green: return "34C759"
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
