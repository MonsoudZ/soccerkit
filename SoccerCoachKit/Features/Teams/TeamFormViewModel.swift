import Foundation

@MainActor
final class TeamFormViewModel: ObservableObject {
    let team: Team?
    @Published var name: String
    @Published var ageGroup: AgeGroup
    @Published var season: String
    @Published var accentName: String
    @Published var defaultPlayerCount: Int
    @Published var defaultOpponentCount: Int
    @Published var defaultConeCount: Int
    @Published var defaultZoneCount: Int

    init(team: Team?) {
        self.team = team
        name = team?.name ?? ""
        ageGroup = team?.ageGroup ?? .u12
        season = team?.season ?? "Fall 2026"
        accentName = team?.accentName ?? "Teal"
        defaultPlayerCount = team?.trainingDefaults.playerCount ?? TrainingBoardDefaults.standard.playerCount
        defaultOpponentCount = team?.trainingDefaults.opponentCount ?? TrainingBoardDefaults.standard.opponentCount
        defaultConeCount = team?.trainingDefaults.coneCount ?? TrainingBoardDefaults.standard.coneCount
        defaultZoneCount = team?.trainingDefaults.zoneCount ?? TrainingBoardDefaults.standard.zoneCount
    }

    var isEditing: Bool { team != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(into store: AppStore) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeason = season.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccent = accentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = TrainingBoardDefaults(
            playerCount: defaultPlayerCount,
            opponentCount: defaultOpponentCount,
            coneCount: defaultConeCount,
            zoneCount: defaultZoneCount
        )

        if let team {
            store.updateTeam(
                Team(
                    id: team.id,
                    name: cleanName,
                    ageGroup: ageGroup,
                    season: cleanSeason,
                    accentName: cleanAccent.isEmpty ? team.accentName : cleanAccent,
                    trainingDefaults: defaults
                )
            )
        } else {
            store.addTeam(name: cleanName, ageGroup: ageGroup, season: cleanSeason.isEmpty ? "Current Season" : cleanSeason)
            var newTeam = store.selectedTeam
            newTeam.trainingDefaults = defaults
            store.updateTeam(newTeam)
        }
    }
}
