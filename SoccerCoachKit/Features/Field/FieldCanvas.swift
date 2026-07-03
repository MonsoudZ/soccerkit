import SwiftUI

struct FieldCanvas: View {
    let tool: BoardTool
    let roster: [Player]
    @Binding var players: [BoardPlayer]
    @Binding var zones: [BoardZone]
    @Binding var lines: [BoardLine]
    @Binding var equipment: [BoardEquipment]
    @Binding var draftLine: BoardLine?
    @Binding var opponentCount: Int
    @Binding var coneCount: Int
    @Binding var zoneCount: Int

    var body: some View {
        GeometryReader { proxy in
            let fieldRect = fittedFieldRect(in: proxy.size)

            ZStack {
                SoccerPitch()
                    .frame(width: fieldRect.width, height: fieldRect.height)
                    .position(x: fieldRect.midX, y: fieldRect.midY)

                ForEach(zones) { zone in
                    ZoneOverlay(zone: zone, fieldRect: fieldRect) { updated in
                        updateZone(updated)
                    }
                }

                ForEach(lines) { line in
                    FieldLine(line: line, fieldRect: fieldRect)
                }

                if let draftLine {
                    FieldLine(line: draftLine, fieldRect: fieldRect, isDraft: true)
                }

                ForEach($equipment) { $item in
                    EquipmentMarker(item: $item, fieldRect: fieldRect)
                }

                ForEach($players) { $player in
                    PlayerMarker(player: $player, fieldRect: fieldRect)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(boardGesture(fieldRect: fieldRect))
        }
    }

    private func boardGesture(fieldRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: tool == .line ? 3 : 0)
            .onChanged { value in
                guard tool == .line, fieldRect.contains(value.startLocation) else { return }
                draftLine = BoardLine(
                    id: UUID(),
                    start: normalize(value.startLocation, in: fieldRect),
                    end: normalize(value.location, in: fieldRect)
                )
            }
            .onEnded { value in
                guard fieldRect.contains(value.location) else {
                    draftLine = nil
                    return
                }

                if tool == .line {
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance > 12, let draftLine {
                        lines.append(draftLine)
                    }
                    draftLine = nil
                } else if hypot(value.translation.width, value.translation.height) < 8 {
                    addItem(at: normalize(value.location, in: fieldRect))
                }
            }
    }

    private func addItem(at point: CGPoint) {
        switch tool {
        case .player:
            let usedIDs = Set(players.compactMap(\.playerID))
            let nextPlayer = roster.first { !usedIDs.contains($0.id) }
            let label = nextPlayer?.name.components(separatedBy: " ").first ?? "Player \(players.filter { $0.side == .team }.count + 1)"
            players.append(
                BoardPlayer(
                    id: UUID(),
                    playerID: nextPlayer?.id,
                    label: label,
                    number: nextPlayer?.number,
                    side: .team,
                    position: point
                )
            )
        case .opponent:
            players.append(
                BoardPlayer(
                    id: UUID(),
                    playerID: nil,
                    label: "OPP \(opponentCount)",
                    number: nil,
                    side: .opponent,
                    position: point
                )
            )
            opponentCount += 1
        case .cone:
            equipment.append(
                BoardEquipment(
                    id: UUID(),
                    label: "Cone \(coneCount)",
                    position: point
                )
            )
            coneCount += 1
        case .zone:
            let origin = CGPoint(x: clamp(point.x - 0.14), y: clamp(point.y - 0.09))
            zones.append(
                BoardZone(
                    id: UUID(),
                    title: "Zone \(zoneCount)",
                    rect: CGRect(x: origin.x, y: origin.y, width: 0.28, height: 0.18)
                )
            )
            zoneCount += 1
        case .line:
            break
        }
    }

    private func updateZone(_ zone: BoardZone) {
        guard let index = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        zones[index] = zone
    }

    private func fittedFieldRect(in size: CGSize) -> CGRect {
        let maxWidth = size.width
        let maxHeight = size.height
        let targetRatio = 68.0 / 105.0
        var width = maxWidth
        var height = width / targetRatio

        if height > maxHeight {
            height = maxHeight
            width = height * targetRatio
        }

        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}
