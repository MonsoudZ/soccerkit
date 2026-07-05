import SwiftUI

struct TeamPicker: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Picker("Team", selection: $store.selectedTeamID) {
            ForEach(store.teams) { team in
                HStack {
                    Circle()
                        .fill(team.accentColor)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(team.name)
                        Text("\(team.ageGroup.rawValue) - \(team.season)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(team.id)
            }
        }
        .pickerStyle(.menu)
    }
}
