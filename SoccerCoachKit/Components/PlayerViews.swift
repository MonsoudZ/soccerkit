import SwiftUI

struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(number: player.number, position: player.position)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.headline)
                Text("\(player.position.rawValue) - Guardian: \(player.guardian)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlayerAvatar: View {
    let number: Int
    let position: PlayerPosition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
            Text("#\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }

    var color: Color {
        switch position {
        case .goalkeeper: return .orange
        case .defender: return .blue
        case .midfielder: return .teal
        case .forward: return .red
        }
    }
}
