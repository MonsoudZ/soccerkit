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
                    ZoneOverlay(zone: zone, fieldRect: fieldRect, tool: tool) { updated in
                        updateZone(updated)
                    } onErase: {
                        zones.removeAll { $0.id == zone.id }
                    }
                }

                ForEach(lines) { line in
                    FieldLine(line: line, fieldRect: fieldRect)
                }

                if let draftLine {
                    FieldLine(line: draftLine, fieldRect: fieldRect, isDraft: true)
                }

                ForEach($equipment) { $item in
                    EquipmentMarker(item: $item, fieldRect: fieldRect, tool: tool) {
                        equipment.removeAll { $0.id == $item.wrappedValue.id }
                    }
                }

                ForEach($players) { $player in
                    PlayerMarker(player: $player, fieldRect: fieldRect, tool: tool) {
                        players.removeAll { $0.id == $player.wrappedValue.id }
                    }
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

                let point = normalize(value.location, in: fieldRect)
                let translation = hypot(value.translation.width, value.translation.height)

                switch tool {
                case .line:
                    if translation > 12, let draftLine {
                        lines.append(draftLine)
                    }
                    draftLine = nil
                case .erase:
                    // Erasing markers is handled by the markers themselves; a tap
                    // on the open pitch removes the nearest drawn line.
                    if translation < 8 {
                        eraseNearestLine(to: point)
                    }
                default:
                    if translation < 8 {
                        addItem(at: point)
                    }
                }
            }
    }

    /// Removes the drawn line closest to `point` (normalized), within a small
    /// tap tolerance, so lines can be erased by tapping them with the Erase tool.
    private func eraseNearestLine(to point: CGPoint) {
        let threshold: CGFloat = 0.04
        var bestID: UUID?
        var bestDistance = threshold
        for line in lines {
            let d = distanceFromPoint(point, toSegment: line.start, line.end)
            if d < bestDistance {
                bestDistance = d
                bestID = line.id
            }
        }
        if let bestID {
            lines.removeAll { $0.id == bestID }
        }
    }

    private func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
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
            let width: CGFloat = 0.28
            let height: CGFloat = 0.18
            // Center on the drop point but keep the whole rect on the pitch, so
            // a zone dropped near the right/bottom edge doesn't extend past 1.0.
            let origin = CGPoint(
                x: min(max(0, point.x - width / 2), 1 - width),
                y: min(max(0, point.y - height / 2), 1 - height)
            )
            zones.append(
                BoardZone(
                    id: UUID(),
                    title: "Zone \(zoneCount)",
                    rect: CGRect(x: origin.x, y: origin.y, width: width, height: height)
                )
            )
            zoneCount += 1
        case .line, .erase:
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
