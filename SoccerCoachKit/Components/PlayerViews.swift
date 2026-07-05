import SwiftUI

struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: Spacing.lg) {
            PlayerAvatar(number: player.number, position: player.position)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.headline)
                Text("\(player.position.rawValue) - Guardian: \(player.guardian)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.accessibilityLabel)
    }
}

struct PlayerAvatar: View {
    let number: Int
    let position: PlayerPosition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(position.color.opacity(0.18))
            Text("#\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(position.color)
        }
        .frame(width: 44, height: 44)
        // Decorative: every use is paired with the player's name/number in text.
        .accessibilityHidden(true)
    }
}
