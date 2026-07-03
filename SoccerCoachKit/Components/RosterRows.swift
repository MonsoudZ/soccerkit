import SwiftUI

enum ContactKind {
    case phone
    case email

    func url(for value: String) -> URL? {
        switch self {
        case .phone:
            let digits = value.filter { !$0.isWhitespace }
            return URL(string: "tel:\(digits)")
        case .email:
            return URL(string: "mailto:\(value)")
        }
    }
}

struct ContactRow: View {
    let label: String
    let value: String
    let kind: ContactKind

    var body: some View {
        LabeledContent(label) {
            if value.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if let url = kind.url(for: value) {
                Link(value, destination: url)
            } else {
                Text(value)
            }
        }
    }
}

struct RSVPRow: View {
    let player: Player
    let status: RSVPStatus
    let setStatus: (RSVPStatus) -> Void

    var body: some View {
        HStack {
            PlayerAvatar(number: player.number, position: player.position)

            VStack(alignment: .leading) {
                Text(player.name)
                    .font(.headline)
                Text(player.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(RSVPStatus.allCases) { option in
                    Button(option.rawValue) {
                        setStatus(option)
                    }
                }
            } label: {
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.16))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
            }
        }
    }
}

extension RSVPStatus {
    var color: Color {
        switch self {
        case .going: return .green
        case .maybe: return .orange
        case .notGoing: return .red
        case .noResponse: return .secondary
        }
    }
}

struct AttendanceRow: View {
    @EnvironmentObject private var store: AppStore
    let player: Player
    let session: TrainingSession

    var status: AttendanceStatus {
        session.attendance[player.id] ?? .absent
    }

    var body: some View {
        HStack {
            PlayerAvatar(number: player.number, position: player.position)

            VStack(alignment: .leading) {
                Text(player.name)
                    .font(.headline)
                Text(player.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(AttendanceStatus.allCases) { option in
                    Button(option.rawValue) {
                        store.setAttendance(option, for: player, in: session)
                    }
                }
            } label: {
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.16))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
    }

    var statusColor: Color {
        switch status {
        case .present: return .green
        case .late: return .orange
        case .excused: return .blue
        case .absent: return .red
        }
    }
}
