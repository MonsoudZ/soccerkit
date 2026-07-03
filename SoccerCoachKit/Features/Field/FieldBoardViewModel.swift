import SwiftUI
import UIKit

@MainActor
final class FieldBoardViewModel: ObservableObject {
    @Published var tool: BoardTool = .player
    @Published var selectedDiagramID: UUID?
    @Published var title = "Game Plan"
    @Published var notes = ""
    @Published var players: [BoardPlayer] = []
    @Published var zones: [BoardZone] = []
    @Published var lines: [BoardLine] = []
    @Published var equipment: [BoardEquipment] = []
    @Published var draftLine: BoardLine?
    @Published var opponentCount = 1
    @Published var coneCount = 1
    @Published var zoneCount = 1
    @Published var exportURL: URL?

    // MARK: - Derived

    func currentDiagram(in store: AppStore) -> TacticsDiagram? {
        guard let selectedDiagramID else { return nil }
        return store.diagrams.first { $0.id == selectedDiagramID }
    }

    func attachmentTitle(in store: AppStore) -> String {
        if let sessionID = currentDiagram(in: store)?.sessionID {
            return store.sessions.first { $0.id == sessionID }?.title ?? "Training Session"
        }

        if let drillID = currentDiagram(in: store)?.drillID {
            return store.drill(for: drillID)?.title ?? "Drill"
        }

        return "Game Plan"
    }

    var helpText: String {
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

    // MARK: - Loading

    func ensureDiagramLoaded(in store: AppStore) {
        if let first = store.teamDiagrams.first {
            selectedDiagramID = first.id
            loadDiagram(first)
        } else {
            let diagram = store.addDiagram(title: "Game Plan")
            selectedDiagramID = diagram.id
            loadDiagram(diagram)
        }
    }

    func loadSelectedDiagram(in store: AppStore) {
        guard let diagram = currentDiagram(in: store) else { return }
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

    // MARK: - Saving

    func saveCurrentDiagram(in store: AppStore) {
        guard let currentDiagram = currentDiagram(in: store) else {
            createNewDiagram(in: store)
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

    func createNewDiagram(in store: AppStore) {
        let diagram = store.addDiagram(title: "Game Plan")
        selectedDiagramID = diagram.id
        loadDiagram(diagram)
    }

    func duplicateCurrentDiagram(in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }
        let copy = store.duplicateDiagram(currentDiagram)
        selectedDiagramID = copy.id
        loadDiagram(copy)
    }

    func attachCurrentDiagram(sessionID: UUID?, drillID: UUID?, in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }
        store.attachDiagram(currentDiagram, sessionID: sessionID, drillID: drillID)
    }

    func resetCurrentBoard(in store: AppStore) {
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

    func clearLines() {
        lines.removeAll()
    }

    func deleteCurrentDiagram(in store: AppStore) {
        guard let currentDiagram = currentDiagram(in: store) else { return }
        store.deleteDiagram(currentDiagram)
        selectedDiagramID = nil
        ensureDiagramLoaded(in: store)
    }

    // MARK: - Export

    func prepareImageExport(in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }

        let renderer = ImageRenderer(content: DiagramExportView(diagram: currentDiagram).frame(width: 900, height: 1390))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeExportName(for: currentDiagram, extension: "png"))
        try? data.write(to: url)
        exportURL = url
    }

    func preparePDFExport(in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }

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
