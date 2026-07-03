import SwiftUI

struct TeamPicker: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Picker("Team", selection: $store.selectedTeamID) {
            ForEach(store.teams) { team in
                VStack(alignment: .leading) {
                    Text(team.name)
                    Text("\(team.ageGroup.rawValue) - \(team.season)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(team.id)
            }
        }
        .pickerStyle(.menu)
    }
}
