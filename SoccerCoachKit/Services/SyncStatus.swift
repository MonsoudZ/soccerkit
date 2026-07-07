import SwiftUI

/// A coach-facing summary of where CloudKit sync stands, surfaced in Settings so
/// sync isn't silent (you can tell if it worked, is offline, or failed).
enum SyncStatus: Equatable {
    case off
    /// No iCloud account signed in on the device.
    case unavailable
    case syncing
    case synced(Date)
    case failed(String)

    var label: String {
        switch self {
        case .off: return "Off"
        case .unavailable: return "iCloud unavailable"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .failed: return "Sync error"
        }
    }

    /// A secondary line (relative time, or the error), if any.
    var detail: String? {
        switch self {
        case .off: return "Turn on to sync across your devices."
        case .unavailable: return "Sign in to iCloud in Settings to sync."
        case .syncing: return nil
        case .synced(let date): return "Last synced \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): return message
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "icloud.slash"
        case .unavailable: return "exclamationmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .failed: return "xmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .off: return .secondary
        case .unavailable, .failed: return .caution
        case .syncing: return .info
        case .synced: return .positive
        }
    }

    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}
