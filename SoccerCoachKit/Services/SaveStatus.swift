import SwiftUI

/// Whether the coach's changes are actually reaching disk.
///
/// The snapshot is sealed before it is written, and sealing needs a key from
/// the Keychain. When the Keychain won't give it up — a background launch
/// before the device's first unlock, or a build that isn't properly signed —
/// the write is deliberately dropped rather than falling back to plaintext.
/// That is the right call for a file holding children's medical notes, but it
/// must not be a silent one: a coach filling in a squad whose changes are only
/// in memory deserves to know before they close the app.
enum SaveStatus: Equatable {
    case saved
    /// A write couldn't be secured, so the change is still only in memory. It
    /// is retried on the next save and when the app leaves the foreground, so
    /// this usually clears itself.
    case unsaved

    var label: String {
        switch self {
        case .saved: return "Saved"
        case .unsaved: return "Not saved"
        }
    }

    var detail: String? {
        switch self {
        case .saved: return nil
        case .unsaved:
            return "This device won't let the app store its encryption key, so recent changes are only in memory. They'll be written as soon as it does — unlocking the device usually fixes it."
        }
    }

    var systemImage: String {
        switch self {
        case .saved: return "checkmark.circle"
        case .unsaved: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .saved: return .positive
        case .unsaved: return .caution
        }
    }
}
