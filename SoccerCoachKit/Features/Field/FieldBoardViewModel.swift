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
        guard let diagram = currentDiagram(in: store) else { return "Game Plan" }

        if let sessionID = diagram.sessionID {
            return store.sessions.first { $0.id == sessionID }?.title ?? "Training Session"
        }
        if let drillID = diagram.drillID {
            return store.drill(for: drillID)?.title ?? "Drill"
        }
        if let gameID = diagram.gameID,
           let game = store.games.first(where: { $0.id == gameID }) {
            return "vs \(game.opponent)"
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
        case .erase:
            return "Tap any player, cone, zone, or line to remove it. (Long-press a marker for Delete too.)"
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
        // A prepared export belongs to the diagram it was rendered from.
        discardExport()
    }

    // MARK: - Saving

    func saveCurrentDiagram(in store: AppStore) {
        guard let currentDiagram = currentDiagram(in: store) else {
            createNewDiagram(in: store)
            return
        }
        store.updateDiagram(board(appliedTo: currentDiagram))
    }

    /// `diagram` with the in-memory board written onto it.
    private func board(appliedTo diagram: TacticsDiagram) -> TacticsDiagram {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = diagram
        updated.title = trimmed.isEmpty ? "Untitled Diagram" : trimmed
        updated.notes = notes
        updated.players = players
        updated.zones = zones
        updated.lines = lines
        updated.equipment = equipment
        return updated
    }

    // MARK: - Autosave

    /// Writes the board to the store if it differs from what's stored.
    ///
    /// The board lives in this view model until something saves it, and the Save
    /// button used to be the only thing that did — so switching team, picking
    /// another diagram, or simply navigating away discarded the work silently.
    /// Every one of those paths now banks the board first. Every other editor in
    /// the app writes through the store as it goes; this brings the board in
    /// line.
    ///
    /// Skips an unchanged board on purpose: `updateDiagram` stamps `updatedAt`,
    /// which reorders the newest-first diagram picker and pushes a sync record,
    /// so saving on every appear/disappear would churn both for no reason.
    func autosave(in store: AppStore) {
        guard let diagram = currentDiagram(in: store) else { return }
        let updated = board(appliedTo: diagram)
        guard updated != diagram else { return }
        store.updateDiagram(updated)
    }

    /// Picker binding that banks the outgoing board before the incoming diagram
    /// loads over it. This replaced an `onChange` on `selectedDiagramID`, which
    /// fires *after* the id has already moved on — by which point the board it
    /// would have saved belongs to the wrong diagram.
    func diagramSelection(in store: AppStore) -> Binding<UUID?> {
        Binding(
            get: { [weak self] in self?.selectedDiagramID },
            set: { [weak self] newValue in
                guard let self, newValue != self.selectedDiagramID else { return }
                self.autosave(in: store)
                self.selectedDiagramID = newValue
                self.loadSelectedDiagram(in: store)
            }
        )
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

    func attachCurrentDiagram(sessionID: UUID? = nil, drillID: UUID? = nil, gameID: UUID? = nil, in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }
        store.attachDiagram(currentDiagram, sessionID: sessionID, drillID: drillID, gameID: gameID)
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

        // Move to whatever is left rather than immediately seeding a replacement.
        // Creating one here would be a second mutation, and the store retires a
        // pending undo as soon as another change lands — so the auto-create would
        // cancel the undo offer for the delete that just happened, and make
        // deleting your last diagram look like nothing happened. `onAppear`'s
        // `ensureDiagramLoaded` still seeds one next time the board is opened.
        if let next = store.teamDiagrams.first {
            selectedDiagramID = next.id
            loadDiagram(next)
        } else {
            selectedDiagramID = nil
            clearBoard()
        }
    }

    /// Empties the board in memory only — no diagram is selected, so there is
    /// nothing to write to.
    private func clearBoard() {
        title = "Game Plan"
        notes = ""
        players = []
        zones = []
        lines = []
        equipment = []
        draftLine = nil
        opponentCount = 1
        coneCount = 1
        zoneCount = 1
        discardExport()
    }

    // MARK: - Export

    func prepareImageExport(in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }

        let renderer = ImageRenderer(content: DiagramExportView(diagram: currentDiagram).frame(width: 900, height: 1390))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return }

        write(data, named: safeExportName(for: currentDiagram, extension: "png"))
    }

    func preparePDFExport(in store: AppStore) {
        saveCurrentDiagram(in: store)
        guard let currentDiagram = currentDiagram(in: store) else { return }

        let size = CGSize(width: 612, height: 792)
        let renderer = ImageRenderer(content: DiagramExportView(diagram: currentDiagram).frame(width: 560, height: 720))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(x: 26, y: 36, width: 560, height: 720))
        }
        write(data, named: safeExportName(for: currentDiagram, extension: "pdf"))
    }

    /// Writes an export to the temporary directory, dropping the one before it.
    ///
    /// The roster, session and settings exporters all clear the previous file;
    /// this one didn't, so every Prepare Image / Prepare PDF left another render
    /// behind — and switching to a differently-named diagram meant a new name and
    /// so a new file rather than an overwrite.
    private func write(_ data: Data, named name: String) {
        discardExport()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return }
        exportURL = url
    }

    /// Removes the prepared export, if there is one. Called before preparing the
    /// next, when the board is torn down, and when the diagram it belongs to goes
    /// away — a stale share link would otherwise offer the wrong diagram.
    func discardExport() {
        if let url = exportURL { try? FileManager.default.removeItem(at: url) }
        exportURL = nil
    }

    private func safeExportName(for diagram: TacticsDiagram, extension fileExtension: String) -> String {
        let base = diagram.title
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return "\(base.isEmpty ? "diagram" : base).\(fileExtension)"
    }
}
