import SwiftUI

struct DiagramPreviewView: View {
    @EnvironmentObject private var store: AppStore
    let diagramID: UUID

    private var diagram: TacticsDiagram? {
        store.diagrams.first { $0.id == diagramID }
    }

    var body: some View {
        Group {
            if let diagram {
                ScrollView {
                    DiagramExportView(diagram: diagram)
                        .padding()
                }
                .screenBackground()
            } else {
                EmptyStateView(title: "Diagram Removed", systemImage: "rectangle.dashed")
            }
        }
        .navigationTitle(diagram?.title ?? "Diagram")
    }
}

struct DiagramExportView: View {
    let diagram: TacticsDiagram

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(diagram.title)
                    .font(.title.weight(.bold))
                Text(diagram.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let fieldRect = CGRect(origin: .zero, size: proxy.size)

                ZStack {
                    SoccerPitch()

                    ForEach(diagram.zones) { zone in
                        StaticZoneOverlay(zone: zone, fieldRect: fieldRect)
                    }

                    ForEach(diagram.lines) { line in
                        FieldLine(line: line, fieldRect: fieldRect)
                    }

                    ForEach(diagram.equipment) { item in
                        StaticEquipmentMarker(item: item, fieldRect: fieldRect)
                    }

                    ForEach(diagram.players) { player in
                        StaticPlayerMarker(player: player, fieldRect: fieldRect)
                    }
                }
            }
            .aspectRatio(68.0 / 105.0, contentMode: .fit)

            if !diagram.notes.isEmpty {
                Text(diagram.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
    }
}

struct StaticPlayerMarker: View {
    let player: BoardPlayer
    let fieldRect: CGRect

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
            .frame(width: 38, height: 38)

            Text(player.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(player.position, in: fieldRect))
    }

    private var fillColor: Color {
        switch player.side {
        case .team: return .blue
        case .opponent: return .red
        }
    }
}

struct StaticEquipmentMarker: View {
    let item: BoardEquipment
    let fieldRect: CGRect

    var body: some View {
        VStack(spacing: 3) {
            ConeShape()
                .fill(Color.orange)
                .frame(width: 26, height: 24)
                .overlay(
                    ConeShape()
                        .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                )

            Text(item.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
        .position(absolute(item.position, in: fieldRect))
    }
}

struct StaticZoneOverlay: View {
    let zone: BoardZone
    let fieldRect: CGRect

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
    }
}

struct FieldLine: View {
    let line: BoardLine
    let fieldRect: CGRect
    var isDraft = false

    var body: some View {
        Path { path in
            path.move(to: absolute(line.start, in: fieldRect))
            path.addLine(to: absolute(line.end, in: fieldRect))
        }
        .stroke(
            Color.white.opacity(isDraft ? 0.5 : 0.95),
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: isDraft ? [8, 6] : [])
        )
        .overlay(alignment: .topLeading) {
            ArrowHead(start: absolute(line.start, in: fieldRect), end: absolute(line.end, in: fieldRect))
                .fill(Color.white.opacity(isDraft ? 0.5 : 0.95))
        }
    }
}

struct ArrowHead: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 12
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let p2 = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))

        var path = Path()
        path.move(to: end)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        return path
    }
}
