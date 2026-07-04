import CoreGraphics
import SwiftUI

struct SubReminder: Identifiable, Hashable {
    let id: UUID
    var minute: Int
    var outPlayerID: UUID
    var inPlayerID: UUID
    var triggered: Bool
    /// Whether the early "heads-up" alert (fired `lead` seconds before `minute`)
    /// has already been shown.
    var preAlertTriggered: Bool = false
}

struct SubLogEntry: Identifiable, Hashable {
    let id: UUID
    var time: Int
    var outPlayerID: UUID
    var inPlayerID: UUID
    var outName: String
    var inName: String
    var note: String
}

enum GamePlayerStatus: String, CaseIterable, Identifiable {
    case available = "Available"
    case late = "Late"
    case injured = "Injured"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .available: return .green
        case .late: return .orange
        case .injured: return .red
        }
    }
}

enum LineupDropTarget {
    case starters
    case starterSlot(UUID)
    case bench
}

enum LineupFormation: String, CaseIterable, Identifiable {
    case balanced = "Balanced"
    case defensive = "Defensive"
    case attacking = "Attacking"

    var id: String { rawValue }

    func slots(for playersOnField: Int) -> [LineupSlot] {
        switch playersOnField {
        case 4:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 1, midfielders: 1, forwards: 1)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 1, forwards: 0)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 1, midfielders: 0, forwards: 2)
            }
        case 7:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 3, forwards: 1)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 2, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 2, forwards: 2)
            }
        case 9:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 3, forwards: 2)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 4, midfielders: 3, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 2, forwards: 3)
            }
        default:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 4, midfielders: 3, forwards: 3)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 5, midfielders: 4, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 4, forwards: 3)
            }
        }
    }

    private func slots(goalkeeper: Int, defenders: Int, midfielders: Int, forwards: Int) -> [LineupSlot] {
        var result: [LineupSlot] = []
        result.append(contentsOf: rowSlots(count: goalkeeper, y: 0.88, label: "GK"))
        result.append(contentsOf: rowSlots(count: defenders, y: 0.68, label: "DEF"))
        result.append(contentsOf: rowSlots(count: midfielders, y: 0.46, label: "MID"))
        result.append(contentsOf: rowSlots(count: forwards, y: 0.22, label: "FWD"))
        return result
    }

    private func rowSlots(count: Int, y: CGFloat, label: String) -> [LineupSlot] {
        guard count > 0 else { return [] }

        let horizontalInset: CGFloat = count == 1 ? 0.5 : 0.18
        let step = count == 1 ? 0 : (1 - horizontalInset * 2) / CGFloat(count - 1)

        return (0..<count).map { index in
            let x = count == 1 ? 0.5 : horizontalInset + CGFloat(index) * step
            return LineupSlot(label: slotLabel(label, index: index, count: count), position: CGPoint(x: x, y: y))
        }
    }

    private func slotLabel(_ label: String, index: Int, count: Int) -> String {
        guard count > 1 else { return label }

        switch index {
        case 0:
            return "L \(label)"
        case count - 1:
            return "R \(label)"
        default:
            return label
        }
    }
}

struct LineupSlot: Identifiable {
    let label: String
    let position: CGPoint
    // Derived from stable content (each slot has a distinct position) so empty
    // slots keep their identity across renders instead of churning every tick.
    var id: String { "\(label)@\(position.x),\(position.y)" }
}

func formatClock(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", remainingSeconds))"
}
