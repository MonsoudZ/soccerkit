import SwiftUI

/// Domain color mappings, centralized so views don't hard-code them.

extension PlayerPosition {
    var color: Color {
        switch self {
        case .goalkeeper: return .caution
        case .defender: return .info
        case .midfielder: return .brand
        case .forward: return .critical
        }
    }
}

extension AttendanceStatus {
    var color: Color {
        switch self {
        case .present: return .positive
        case .late: return .caution
        case .excused: return .info
        case .absent: return .critical
        }
    }
}

extension CalendarEventKind {
    /// The calendar legend. Reuses semantic tokens where the meaning lines up
    /// (a game is informational blue, a tournament is caution amber, a scrimmage
    /// is positive green, a meeting is the brand tint) and adds adaptive
    /// light/dark values for the rest so nothing is a raw system color.
    var color: Color {
        switch self {
        case .practice: return Color(light: 0x0E7490, dark: 0x2DD4BF)   // teal
        case .game: return .info
        case .tournament: return .caution
        case .scrimmage: return .positive
        case .social: return Color(light: 0xBE185D, dark: 0xF472B6)     // pink
        case .meeting: return .brand
        case .other: return Color(light: 0x6B7280, dark: 0x9CA3AF)      // gray
        }
    }
}
