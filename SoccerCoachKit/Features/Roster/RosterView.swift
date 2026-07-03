import SwiftUI

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = RosterViewModel()

    var body: some View {
        List {
            Section("Team Rules") {
                Picker("Age Group", selection: ageGroupBinding) {
                    ForEach(AgeGroup.allCases) { ageGroup in
                        Text(ageGroup.rawValue).tag(ageGroup)
                    }
                }

                LabeledContent("Roster Limit", value: "\(store.roster.count) / \(store.selectedTeam.ageGroup.maxRosterSize)")
                LabeledContent("Game Format", value: "\(store.selectedTeam.ageGroup.playersOnField)v\(store.selectedTeam.ageGroup.playersOnField)")

                if store.roster.count > store.selectedTeam.ageGroup.maxRosterSize {
                    Label("Roster is over the selected age group's max.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(store.roster) { player in
                    NavigationLink {
                        PlayerDetailView(playerID: player.id)
                    } label: {
                        PlayerRow(player: player)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(player, from: store)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(store.selectedTeam.ageGroup.rawValue) Roster")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            Button {
                viewModel.showingAddPlayer = true
            } label: {
                Label("Add Player", systemImage: "plus")
            }
        }
        .sheet(isPresented: $viewModel.showingAddPlayer) {
            NavigationStack {
                PlayerFormView()
            }
        }
    }

    private var ageGroupBinding: Binding<AgeGroup> {
        Binding {
            store.selectedTeam.ageGroup
        } set: { newValue in
            store.setAgeGroup(newValue, for: store.selectedTeam)
        }
    }
}
