import Foundation

@MainActor
final class SessionFormViewModel: ObservableObject {
    let session: TrainingSession?
    @Published var title: String
    @Published var date: Date
    @Published var objective: String
    @Published var weather: String
    @Published var blocks: [TrainingBlock]
    @Published var selectedDrillID: UUID?
    @Published var selectedDiagramID: UUID?
    @Published var newBlockTopic: String
    @Published var newBlockMinutes: Int
    @Published var newBlockFocus: String
    @Published var newBlockPitchArea: String
    @Published var newBlockDetails: String
    @Published var newBlockIntensity: Int
    @Published var selectedPositions: Set<PlayerPosition>

    init(session: TrainingSession?, initialDate: Date?) {
        self.session = session
        title = session?.title ?? ""
        date = session?.date ?? initialDate ?? Date()
        objective = session?.objective ?? ""
        weather = session?.weather ?? "Clear"
        blocks = session?.blocks ?? []
        selectedDrillID = session?.blocks.first?.drillID
        selectedDiagramID = session?.blocks.first?.diagramID
        newBlockTopic = ""
        newBlockMinutes = 15
        newBlockFocus = ""
        newBlockPitchArea = ""
        newBlockDetails = ""
        newBlockIntensity = 3
        selectedPositions = []
    }

    var isEditing: Bool { session != nil }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var planMinutes: Int {
        blocks.reduce(0) { $0 + $1.minutes }
    }

    private var cleanWeather: String {
        let trimmed = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    func selectedDrillDiagrams(in store: AppStore) -> [TacticsDiagram] {
        guard let selectedDrillID, let drill = store.drill(for: selectedDrillID) else { return [] }
        return store.diagrams(for: drill)
    }

    func diagrams(for block: TrainingBlock, in store: AppStore) -> [TacticsDiagram] {
        guard let drill = store.drill(for: block.drillID) else { return [] }
        return store.diagrams(for: drill)
    }

    func prepareDefaultDrillSelection(in store: AppStore) {
        guard selectedDrillID == nil, let drill = store.teamDrills.first else { return }
        selectedDrillID = drill.id
        applyDrillDefaults(drill, in: store)
    }

    func handleDrillSelectionChange(in store: AppStore) {
        if let drillID = selectedDrillID, let drill = store.drill(for: drillID) {
            clearSectionDraft()
            applyDrillDefaults(drill, in: store)
        }
    }

    func addSelectedDrillBlock(in store: AppStore) {
        guard let drillID = selectedDrillID else { return }
        guard blocks.count < 6 else { return }
        let cleanFocus = newBlockFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTopic = newBlockTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPitchArea = newBlockPitchArea.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = newBlockDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFocus = store.drill(for: drillID)?.coachingPoints.first ?? "Run the drill with game speed."
        let fallbackTopic = store.drill(for: drillID)?.title ?? "Training Section"
        let positions = PlayerPosition.allCases.filter { selectedPositions.contains($0) }

        blocks.append(
            TrainingBlock(
                id: UUID(),
                drillID: drillID,
                minutes: newBlockMinutes,
                focus: cleanFocus.isEmpty ? fallbackFocus : cleanFocus,
                diagramID: selectedDiagramID,
                topic: cleanTopic.isEmpty ? fallbackTopic : cleanTopic,
                positions: positions,
                pitchArea: cleanPitchArea,
                details: cleanDetails,
                intensity: newBlockIntensity
            )
        )

        if let drill = store.drill(for: drillID) {
            clearSectionDraft()
            applyDrillDefaults(drill, in: store)
        }
    }

    func clearSectionDraft() {
        newBlockTopic = ""
        newBlockFocus = ""
        newBlockPitchArea = ""
        newBlockDetails = ""
        newBlockIntensity = 3
        selectedPositions.removeAll()
    }

    private func applyDrillDefaults(_ drill: Drill, in store: AppStore) {
        newBlockMinutes = drill.durationMinutes
        if newBlockTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockTopic = drill.title
        }
        if newBlockFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockFocus = drill.coachingPoints.first ?? ""
        }
        if newBlockPitchArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockPitchArea = drill.fieldSize
        }
        if newBlockDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockDetails = drill.fieldSetup
        }
        selectedDiagramID = store.diagrams(for: drill).first?.id
    }

    func save(into store: AppStore) {
        if let session {
            var updated = session
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.date = date
            updated.objective = objective
            updated.weather = cleanWeather
            updated.blocks = blocks
            store.updateSession(updated)
        } else {
            store.addSession(title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date, objective: objective, weather: cleanWeather, blocks: blocks)
        }
    }
}
