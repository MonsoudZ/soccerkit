import SwiftUI

/// Shared point-marker gesture: with the Erase tool, a tap removes the marker;
/// otherwise a drag repositions it. Erase mode never repositions, so tapping to
/// delete can't accidentally nudge a piece.
private func markerGesture(
    tool: BoardTool,
    position: Binding<CGPoint>,
    dragStart: Binding<CGPoint?>,
    fieldRect: CGRect,
    onErase: @escaping () -> Void
) -> some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            guard tool != .erase else { return }
            let start = dragStart.wrappedValue ?? position.wrappedValue
            dragStart.wrappedValue = start
            position.wrappedValue = CGPoint(
                x: clamp(start.x + value.translation.width / fieldRect.width),
                y: clamp(start.y + value.translation.height / fieldRect.height)
            )
        }
        .onEnded { value in
            dragStart.wrappedValue = nil
            if tool == .erase, hypot(value.translation.width, value.translation.height) < 10 {
                onErase()
            }
        }
}

struct PlayerMarker: View {
    @Binding var player: BoardPlayer
    let fieldRect: CGRect
    var tool: BoardTool = .player
    var onErase: () -> Void = {}
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: Spacing.xs) {
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
            .overlay(eraseHint)

            Text(player.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(player.position, in: fieldRect))
        .gesture(markerGesture(tool: tool, position: $player.position, dragStart: $dragStart, fieldRect: fieldRect, onErase: onErase))
        .contextMenu {
            Button(role: .destructive, action: onErase) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(player.label)
        .accessibilityHint(tool == .erase ? "Tap to remove" : "Drag to reposition")
    }

    @ViewBuilder private var eraseHint: some View {
        if tool == .erase {
            Circle().stroke(Color.critical, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
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
    var tool: BoardTool = .cone
    var onErase: () -> Void = {}
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 3) {
            ConeShape()
                .fill(Color.orange)
                .frame(width: 30, height: 28)
                .overlay(
                    ConeShape()
                        .stroke(tool == .erase ? Color.critical : Color.white.opacity(0.85),
                                lineWidth: tool == .erase ? 2 : 1.5)
                )
                .shadow(radius: 2, y: 1)

            Text(item.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, Spacing.xxs)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(item.position, in: fieldRect))
        .gesture(markerGesture(tool: tool, position: $item.position, dragStart: $dragStart, fieldRect: fieldRect, onErase: onErase))
        .contextMenu {
            Button(role: .destructive, action: onErase) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(item.label)
        .accessibilityHint(tool == .erase ? "Tap to remove" : "Drag to reposition")
    }
}

struct ZoneOverlay: View {
    let zone: BoardZone
    let fieldRect: CGRect
    var tool: BoardTool = .zone
    let onChange: (BoardZone) -> Void
    var onErase: () -> Void = {}
    @State private var dragStart: CGRect?

    private var strokeColor: Color { tool == .erase ? .critical : .yellow }

    var body: some View {
        let rect = absolute(zone.rect, in: fieldRect)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(Color.yellow.opacity(0.24))
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            Text(zone.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black.opacity(0.72))
                .padding(Spacing.sm)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard tool != .erase else { return }
                    let start = dragStart ?? zone.rect
                    dragStart = start
                    let dx = value.translation.width / fieldRect.width
                    let dy = value.translation.height / fieldRect.height
                    var updated = zone
                    updated.rect.origin.x = clamp(start.origin.x + dx, max: 1 - zone.rect.width)
                    updated.rect.origin.y = clamp(start.origin.y + dy, max: 1 - zone.rect.height)
                    onChange(updated)
                }
                .onEnded { value in
                    dragStart = nil
                    if tool == .erase, hypot(value.translation.width, value.translation.height) < 10 {
                        onErase()
                    }
                }
        )
        .contextMenu {
            Button(role: .destructive, action: onErase) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(zone.title)
        .accessibilityHint(tool == .erase ? "Tap to remove" : "Drag to reposition")
    }
}
