import CoreGraphics
import Foundation

extension AppStore {
    // MARK: - Diagrams

    func diagrams(for session: TrainingSession) -> [TacticsDiagram] {
        let sectionDiagramIDs = Set(session.blocks.compactMap(\.diagramID))
        return diagrams
            .filter { $0.sessionID == session.id || sectionDiagramIDs.contains($0.id) }
            .removingDuplicates()
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func diagrams(for drill: Drill) -> [TacticsDiagram] {
        diagrams
            .filter { $0.drillID == drill.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func diagrams(forGameID gameID: UUID) -> [TacticsDiagram] {
        diagrams
            .filter { $0.gameID == gameID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func addDiagram(title: String, sessionID: UUID? = nil, drillID: UUID? = nil) -> TacticsDiagram {
        let defaults = defaultBoardPieces(for: selectedTeam)
        let diagram = TacticsDiagram(
            id: UUID(),
            teamID: selectedTeamID,
            title: title,
            notes: "",
            sessionID: sessionID,
            drillID: drillID,
            players: defaults.players,
            zones: defaults.zones,
            lines: [],
            equipment: defaults.equipment,
            updatedAt: Date()
        )
        diagrams.append(diagram)
        return diagram
    }

    func defaultBoardPieces(for team: Team) -> (players: [BoardPlayer], zones: [BoardZone], equipment: [BoardEquipment]) {
        let defaults = team.trainingDefaults
        // Resolve the team's roster through active memberships (sorted by number).
        let teamRoster = players(inTeam: team.id)
        let teamPlayers = Array(teamRoster.prefix(defaults.playerCount)).enumerated().map { index, player in
            BoardPlayer(
                id: UUID(),
                playerID: player.id,
                label: player.name.components(separatedBy: " ").first ?? "Player \(index + 1)",
                number: player.number,
                side: .team,
                position: defaultPlayerPosition(index: index, count: max(defaults.playerCount, 1))
            )
        }

        let fillInPlayers: [BoardPlayer]
        if teamPlayers.count < defaults.playerCount {
            fillInPlayers = (teamPlayers.count..<defaults.playerCount).map { index in
                BoardPlayer(
                    id: UUID(),
                    playerID: nil,
                    label: "Player \(index + 1)",
                    number: nil,
                    side: .team,
                    position: defaultPlayerPosition(index: index, count: max(defaults.playerCount, 1))
                )
            }
        } else {
            fillInPlayers = []
        }

        let opponents = (0..<defaults.opponentCount).map { index in
            BoardPlayer(
                id: UUID(),
                playerID: nil,
                label: "OPP \(index + 1)",
                number: nil,
                side: .opponent,
                position: defaultOpponentPosition(index: index, count: max(defaults.opponentCount, 1))
            )
        }

        let zones = (0..<defaults.zoneCount).map { index in
            BoardZone(
                id: UUID(),
                title: "Zone \(index + 1)",
                rect: CGRect(x: 0.18 + CGFloat(index % 2) * 0.34, y: 0.32 + CGFloat(index / 2) * 0.2, width: 0.28, height: 0.18)
            )
        }

        let equipment = (0..<defaults.coneCount).map { index in
            BoardEquipment(
                id: UUID(),
                label: "Cone \(index + 1)",
                position: defaultConePosition(index: index, count: max(defaults.coneCount, 1))
            )
        }

        return (teamPlayers + fillInPlayers + opponents, zones, equipment)
    }

    func updateDiagram(_ diagram: TacticsDiagram) {
        guard let index = diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        var updated = diagram
        updated.updatedAt = Date()
        diagrams[index] = updated
    }

    func duplicateDiagram(_ diagram: TacticsDiagram) -> TacticsDiagram {
        let copy = TacticsDiagram(
            id: UUID(),
            teamID: diagram.teamID,
            title: "\(diagram.title) Copy",
            notes: diagram.notes,
            // A duplicate starts detached, so it doesn't double-attach to the
            // original's session/drill.
            sessionID: nil,
            drillID: nil,
            players: diagram.players,
            zones: diagram.zones,
            lines: diagram.lines,
            equipment: diagram.equipment,
            updatedAt: Date()
        )
        diagrams.append(copy)
        return copy
    }

    func attachDiagram(_ diagram: TacticsDiagram, to sessionID: UUID?) {
        attachDiagram(diagram, sessionID: sessionID, drillID: nil, gameID: nil)
    }

    func attachDiagram(_ diagram: TacticsDiagram, toDrillID drillID: UUID?) {
        attachDiagram(diagram, sessionID: nil, drillID: drillID, gameID: nil)
    }

    /// Attaches a diagram to at most one owner — a session, a drill, or a game.
    /// A diagram is a plan for one thing, so setting an owner clears the others.
    func attachDiagram(_ diagram: TacticsDiagram, sessionID: UUID?, drillID: UUID?, gameID: UUID? = nil) {
        guard let index = diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        diagrams[index].sessionID = sessionID
        diagrams[index].drillID = drillID
        diagrams[index].gameID = gameID
        diagrams[index].updatedAt = Date()
    }

    func deleteDiagram(_ diagram: TacticsDiagram) {
        batch {
            diagrams.removeAll { $0.id == diagram.id }
            sessions = sessions.map { session in
                var updated = session
                updated.blocks = updated.blocks.map { block in
                    var updatedBlock = block
                    if updatedBlock.diagramID == diagram.id {
                        updatedBlock.diagramID = nil
                    }
                    return updatedBlock
                }
                return updated
            }
        }
    }


    // MARK: - Board layout helpers

    private func defaultPlayerPosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = CGFloat(column + 1) / CGFloat(columns + 1)
        let y = 0.62 + CGFloat(row) * (0.24 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: min(y, 0.86))
    }

    private func defaultOpponentPosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = CGFloat(column + 1) / CGFloat(columns + 1)
        let y = 0.18 + CGFloat(row) * (0.22 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: min(y, 0.42))
    }

    private func defaultConePosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = 0.18 + CGFloat(column) * (0.64 / CGFloat(max(columns - 1, 1)))
        let y = 0.46 + CGFloat(row) * (0.12 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: y)
    }
}
