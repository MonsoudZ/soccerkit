import SwiftUI

struct PlayerMarker: View {
    @Binding var player: BoardPlayer
    let fieldRect: CGRect
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fillColor)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                Text(player.number.map(String.init) ?? "X")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(radius: 3, y: 2)

            Text(player.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(player.position, in: fieldRect))
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? player.position
                    dragStart = start
                    player.position = CGPoint(
                        x: clamp(start.x + value.translation.width / fieldRect.width),
                        y: clamp(start.y + value.translation.height / fieldRect.height)
                    )
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .accessibilityLabel(player.label)
    }

    private var fillColor: Color {
        switch player.side {
        case .team: return .blue
        case .opponent: return .red
        }
    }
}

struct EquipmentMarker: View {
    @Binding var item: BoardEquipment
    let fieldRect: CGRect
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 3) {
            ConeShape()
                .fill(Color.orange)
                .frame(width: 30, height: 28)
                .overlay(
                    ConeShape()
                        .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                )
                .shadow(radius: 2, y: 1)

            Text(item.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(item.position, in: fieldRect))
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? item.position
                    dragStart = start
                    item.position = CGPoint(
                        x: clamp(start.x + value.translation.width / fieldRect.width),
                        y: clamp(start.y + value.translation.height / fieldRect.height)
                    )
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .accessibilityLabel(item.label)
    }
}

struct ZoneOverlay: View {
    let zone: BoardZone
    let fieldRect: CGRect
    let onChange: (BoardZone) -> Void
    @State private var dragStart: CGRect?

    var body: some View {
        let rect = absolute(zone.rect, in: fieldRect)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(Color.yellow.opacity(0.24))
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            Text(zone.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black.opacity(0.72))
                .padding(6)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? zone.rect
                    dragStart = start
                    let dx = value.translation.width / fieldRect.width
                    let dy = value.translation.height / fieldRect.height
                    var updated = zone
                    updated.rect.origin.x = clamp(start.origin.x + dx, max: 1 - zone.rect.width)
                    updated.rect.origin.y = clamp(start.origin.y + dy, max: 1 - zone.rect.height)
                    onChange(updated)
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .accessibilityLabel(zone.title)
    }
}
