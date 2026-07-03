import Foundation

@MainActor
final class DrillFormViewModel: ObservableObject {
    let drill: Drill?
    @Published var title: String
    @Published var teamID: UUID?
    @Published var category: DrillCategory
    @Published var tagsText: String
    @Published var durationMinutes: Int
    @Published var equipmentText: String
    @Published var fieldSize: String
    @Published var fieldSetup: String
    @Published var coachingPointsText: String
    @Published var progressionsText: String
    @Published var regressionsText: String

    init(drill: Drill?) {
        self.drill = drill
        title = drill?.title ?? ""
        teamID = drill?.teamID
        category = drill?.category ?? .technical
        tagsText = drill?.tags.joined(separator: ", ") ?? ""
        durationMinutes = drill?.durationMinutes ?? 15
        equipmentText = drill?.equipment.joined(separator: "\n") ?? ""
        fieldSize = drill?.fieldSize ?? ""
        fieldSetup = drill?.fieldSetup ?? ""
        coachingPointsText = drill?.coachingPoints.joined(separator: "\n") ?? ""
        progressionsText = drill?.progressions.joined(separator: "\n") ?? ""
        regressionsText = drill?.regressions.joined(separator: "\n") ?? ""
    }

    var isEditing: Bool { drill != nil }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareDefaultTeam(in store: AppStore) {
        guard drill == nil, teamID == nil else { return }
        teamID = store.selectedTeamID
    }

    func save(into store: AppStore) {
        let equipment = lines(from: equipmentText)
        let points = lines(from: coachingPointsText)
        let progressions = lines(from: progressionsText)
        let regressions = lines(from: regressionsText)
        let tags = tagsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .removingDuplicates()

        if let drill {
            store.updateDrill(
                Drill(
                    id: drill.id,
                    teamID: teamID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    tags: tags,
                    durationMinutes: durationMinutes,
                    equipment: equipment,
                    fieldSize: fieldSize.trimmingCharacters(in: .whitespacesAndNewlines),
                    fieldSetup: fieldSetup,
                    coachingPoints: points,
                    progressions: progressions,
                    regressions: regressions
                )
            )
        } else {
            store.addDrill(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                teamID: teamID,
                category: category,
                tags: tags,
                durationMinutes: durationMinutes,
                equipment: equipment,
                fieldSize: fieldSize.trimmingCharacters(in: .whitespacesAndNewlines),
                fieldSetup: fieldSetup,
                coachingPoints: points,
                progressions: progressions,
                regressions: regressions
            )
        }
    }

    private func lines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
