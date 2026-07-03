import SwiftUI
import UIKit

enum BoardTool: String, CaseIterable, Identifiable {
    case player = "Player"
    case opponent = "Opposition"
    case cone = "Cone"
    case zone = "Zone"
    case line = "Line"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .player: return "person.crop.circle.fill"
        case .opponent: return "circle.hexagongrid.circle.fill"
        case .cone: return "triangle.fill"
        case .zone: return "square.dashed"
        case .line: return "arrow.up.right"
        }
    }
}

struct FieldBoardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tool: BoardTool = .player
    @State private var selectedDiagramID: UUID?
    @State private var title = "Game Plan"
    @State private var notes = ""
    @State private var players: [BoardPlayer] = []
    @State private var zones: [BoardZone] = []
    @State private var lines: [BoardLine] = []
    @State private var equipment: [BoardEquipment] = []
    @State private var draftLine: BoardLine?
    @State private var opponentCount = 1
    @State private var coneCount = 1
    @State private var zoneCount = 1
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            boardToolbar

            FieldCanvas(
                tool: tool,
                roster: store.roster,
                players: $players,
                zones: $zones,
                lines: $lines,
                equipment: $equipment,
                draftLine: $draftLine,
                opponentCount: $opponentCount,
                coneCount: $coneCount,
                zoneCount: $zoneCount
            )
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: ensureDiagramLoaded)
        .onChange(of: store.selectedTeamID) { _ in
            selectedDiagramID = nil
            ensureDiagramLoaded()
        }
        .onChange(of: selectedDiagramID) { _ in
            loadSelectedDiagram()
        }
        .toolbar {
            Button {
                saveCurrentDiagram()
            } label: {
                Label("Save Diagram", systemImage: "square.and.arrow.down")
            }

            Button {
                duplicateCurrentDiagram()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .disabled(currentDiagram == nil)

            Menu {
                Button("Prepare Image") {
                    prepareImageExport()
                }

                Button("Prepare PDF") {
                    preparePDFExport()
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button {
                lines.removeAll()
            } label: {
                Label("Clear Lines", systemImage: "scribble.variable")
            }

            Button(role: .destructive) {
                resetCurrentBoard()
            } label: {
                Label("Reset to Team Defaults", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                deleteCurrentDiagram()
            } label: {
                Label("Delete Diagram", systemImage: "trash")
            }
            .disabled(currentDiagram == nil)
        }
    }

    private var boardToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Diagram", selection: $selectedDiagramID) {
                    ForEach(store.teamDiagrams) { diagram in
                        Text(diagram.title).tag(Optional(diagram.id))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    createNewDiagram()
                } label: {
                    Label("New Diagram", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            TextField("Diagram title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Diagram notes", text: $notes)
                .textFieldStyle(.roundedBorder)

            Menu {
                Button("Game Plan") {
                    attachCurrentDiagram(sessionID: nil, drillID: nil)
                }

                if !store.teamSessions.isEmpty {
                    Menu("Training Session") {
                        ForEach(store.teamSessions) { session in
                            Button(session.title) {
                                attachCurrentDiagram(sessionID: session.id, drillID: nil)
                            }
                        }
                    }
                }

                if !store.teamDrills.isEmpty {
                    Menu("Drill") {
                        ForEach(store.teamDrills) { drill in
                            Button(drill.title) {
                                attachCurrentDiagram(sessionID: nil, drillID: drill.id)
                            }
                        }
                    }
                }
            } label: {
                Label(attachmentTitle, systemImage: "paperclip")
                    .font(.caption)
            }

            Picker("Board Tool", selection: $tool) {
                ForEach(BoardTool.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(helpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var currentDiagram: TacticsDiagram? {
        guard let selectedDiagramID else { return nil }
        return store.diagrams.first { $0.id == selectedDiagramID }
    }

    private var attachmentTitle: String {
        if let sessionID = currentDiagram?.sessionID {
            return store.sessions.first { $0.id == sessionID }?.title ?? "Training Session"
        }

        if let drillID = currentDiagram?.drillID {
            return store.drill(for: drillID)?.title ?? "Drill"
        }

        return "Game Plan"
    }

    private var helpText: String {
        switch tool {
        case .player:
            return "Tap the field to add the next roster player. Drag any player to reposition."
        case .opponent:
            return "Tap the field to add an opposition marker. Drag markers into shape."
        case .cone:
            return "Tap the field to add a cone. Drag cones to build gates, grids, or channels."
        case .zone:
            return "Tap to add a coaching zone. Drag zones to move them."
        case .line:
            return "Drag across the field to draw a pass, run, or movement line."
        }
    }

    private func ensureDiagramLoaded() {
        if let first = store.teamDiagrams.first {
            selectedDiagramID = first.id
            loadDiagram(first)
        } else {
            let diagram = store.addDiagram(title: "Game Plan")
            selectedDiagramID = diagram.id
            loadDiagram(diagram)
        }
    }

    private func loadSelectedDiagram() {
        guard let diagram = currentDiagram else { return }
        loadDiagram(diagram)
    }

    private func loadDiagram(_ diagram: TacticsDiagram) {
        title = diagram.title
        notes = diagram.notes
        players = diagram.players
        zones = diagram.zones
        lines = diagram.lines
        equipment = diagram.equipment
        draftLine = nil
        opponentCount = players.filter { $0.side == .opponent }.count + 1
        coneCount = equipment.count + 1
        zoneCount = zones.count + 1
        exportURL = nil
    }

    private func saveCurrentDiagram() {
        guard let currentDiagram else {
            createNewDiagram()
            return
        }

        var updated = currentDiagram
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Diagram" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = notes
        updated.players = players
        updated.zones = zones
        updated.lines = lines
        updated.equipment = equipment
        store.updateDiagram(updated)
        selectedDiagramID = updated.id
    }

    private func createNewDiagram() {
        let diagram = store.addDiagram(title: "Game Plan")
        selectedDiagramID = diagram.id
        loadDiagram(diagram)
    }

    private func duplicateCurrentDiagram() {
        saveCurrentDiagram()
        guard let currentDiagram else { return }
        let copy = store.duplicateDiagram(currentDiagram)
        selectedDiagramID = copy.id
        loadDiagram(copy)
    }

    private func attachCurrentDiagram(sessionID: UUID?, drillID: UUID?) {
        saveCurrentDiagram()
        guard let currentDiagram else { return }
        store.attachDiagram(currentDiagram, sessionID: sessionID, drillID: drillID)
    }

    private func resetCurrentBoard() {
        let defaults = store.defaultBoardPieces(for: store.selectedTeam)
        players = defaults.players
        zones = defaults.zones
        lines.removeAll()
        equipment = defaults.equipment
        draftLine = nil
        opponentCount = players.filter { $0.side == .opponent }.count + 1
        coneCount = equipment.count + 1
        zoneCount = zones.count + 1
    }

    private func deleteCurrentDiagram() {
        guard let currentDiagram else { return }
        store.deleteDiagram(currentDiagram)
        selectedDiagramID = nil
        ensureDiagramLoaded()
    }

    @MainActor
    private func prepareImageExport() {
        saveCurrentDiagram()
        guard let currentDiagram else { return }

        let renderer = ImageRenderer(content: DiagramExportView(diagram: currentDiagram).frame(width: 900, height: 1390))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeExportName(for: currentDiagram, extension: "png"))
        try? data.write(to: url)
        exportURL = url
    }

    @MainActor
    private func preparePDFExport() {
        saveCurrentDiagram()
        guard let currentDiagram else { return }

        let size = CGSize(width: 612, height: 792)
        let renderer = ImageRenderer(content: DiagramExportView(diagram: currentDiagram).frame(width: 560, height: 720))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeExportName(for: currentDiagram, extension: "pdf"))
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(x: 26, y: 36, width: 560, height: 720))
        }
        try? data.write(to: url)
        exportURL = url
    }

    private func safeExportName(for diagram: TacticsDiagram, extension fileExtension: String) -> String {
        let base = diagram.title
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return "\(base.isEmpty ? "diagram" : base).\(fileExtension)"
    }
}

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

struct SoccerPitch: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let line = Color.white.opacity(0.9)

            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.46, blue: 0.22), Color(red: 0.04, green: 0.36, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.045) : Color.clear)
                    }
                }

                Rectangle()
                    .stroke(line, lineWidth: 3)
                    .padding(8)

                Path { path in
                    path.move(to: CGPoint(x: 8, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width - 8, y: size.height / 2))
                }
                .stroke(line, lineWidth: 2)

                Circle()
                    .stroke(line, lineWidth: 2)
                    .frame(width: size.width * 0.26, height: size.width * 0.26)

                penaltyBox(atTop: true, size: size)
                    .stroke(line, lineWidth: 2)

                penaltyBox(atTop: false, size: size)
                    .stroke(line, lineWidth: 2)

                goalBox(atTop: true, size: size)
                    .stroke(line, lineWidth: 2)

                goalBox(atTop: false, size: size)
                    .stroke(line, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func penaltyBox(atTop: Bool, size: CGSize) -> Path {
        Path { path in
            let width = size.width * 0.62
            let height = size.height * 0.16
            let x = (size.width - width) / 2
            let y = atTop ? 8 : size.height - height - 8
            path.addRect(CGRect(x: x, y: y, width: width, height: height))
        }
    }

    private func goalBox(atTop: Bool, size: CGSize) -> Path {
        Path { path in
            let width = size.width * 0.32
            let height = size.height * 0.065
            let x = (size.width - width) / 2
            let y = atTop ? 8 : size.height - height - 8
            path.addRect(CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

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

struct ConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.24))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.24))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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

private func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(
        x: clamp((point.x - rect.minX) / rect.width),
        y: clamp((point.y - rect.minY) / rect.height)
    )
}

private func absolute(_ point: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
}

private func absolute(_ normalizedRect: CGRect, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + normalizedRect.minX * rect.width,
        y: rect.minY + normalizedRect.minY * rect.height,
        width: normalizedRect.width * rect.width,
        height: normalizedRect.height * rect.height
    )
}

private func clamp(_ value: CGFloat, min: CGFloat = 0, max: CGFloat = 1) -> CGFloat {
    Swift.min(Swift.max(value, min), max)
}
