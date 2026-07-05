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
