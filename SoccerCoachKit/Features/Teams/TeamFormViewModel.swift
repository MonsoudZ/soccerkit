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
            // Start from the stored team rather than rebuilding it, so fields
            // this form doesn't ask about survive. Rebuilding dropped
            // `organizationID`, which `Team.init` then defaulted to the personal
            // org — harmless while that is the only org there is, and a team
            // silently leaving its club the moment clubs exist.
            var updated = team
            updated.name = cleanName
            updated.season = cleanSeason
            if !cleanAccent.isEmpty { updated.accentName = cleanAccent }
            updated.trainingDefaults = defaults
            // Only write the age group when the coach actually moved the picker.
            // `ageGroup` resolves an unknown stored label to the nearest band we
            // know, so assigning it back unconditionally rewrote a team this
            // build doesn't fully understand — a U21 team became U19 because
            // someone corrected a typo in its name, and sync is last-write-wins.
            // (Re-picking the band already shown is therefore a no-op, which is
            // the safe direction: it never discards the label the coach chose.)
            if ageGroup != team.ageGroup { updated.ageGroup = ageGroup }
            // The coach's match rules stay put; clamp the minutes goal in case
            // the age group was lowered here.
            updated.defaultMinimumMinutes = min(team.defaultMinimumMinutes, ageGroup.defaultGameMinutes)
            store.updateTeam(updated)
        } else {
            store.addTeam(name: cleanName, ageGroup: ageGroup, season: cleanSeason.isEmpty ? "Current Season" : cleanSeason)
            var newTeam = store.selectedTeam
            newTeam.trainingDefaults = defaults
            if !cleanAccent.isEmpty { newTeam.accentName = cleanAccent }
            store.updateTeam(newTeam)
        }
    }
}
