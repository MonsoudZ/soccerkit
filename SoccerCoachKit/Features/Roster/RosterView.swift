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

                Picker("Match Periods", selection: periodFormatBinding) {
                    ForEach(PeriodFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Stepper("Min. Minutes / Player: \(store.selectedTeam.defaultMinimumMinutes)", value: minimumMinutesBinding, in: 0...store.selectedTeam.ageGroup.defaultGameMinutes)

                if store.roster.count > store.selectedTeam.ageGroup.maxRosterSize {
                    Label("Roster is over the selected age group's max.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                let players = viewModel.filteredRoster(in: store)
                if players.isEmpty {
                    InlineEmptyView(
                        title: viewModel.isFiltering ? "No Matches" : "No Players Yet",
                        systemImage: viewModel.isFiltering ? "magnifyingglass" : "person.3",
                        message: viewModel.isFiltering ? "No players match your search or filter." : "Add players to build out this team's roster."
                    )
                } else {
                    ForEach(players) { player in
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
                }
            } header: {
                HStack {
                    Text("\(store.selectedTeam.ageGroup.rawValue) Roster")
                    if viewModel.isFiltering {
                        Spacer()
                        Text("\(viewModel.filteredRoster(in: store).count) of \(store.roster.count)")
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .themedList()
        .searchable(text: $viewModel.searchText, prompt: "Search name, number, or position")
        .toolbar {
            Menu {
                Picker("Position", selection: $viewModel.positionFilter) {
                    Text("All Positions").tag(PlayerPosition?.none)
                    ForEach(PlayerPosition.allCases) { position in
                        Text(position.rawValue).tag(Optional(position))
                    }
                }
                if viewModel.isFiltering {
                    Divider()
                    Button("Clear Filters", role: .destructive) {
                        viewModel.clearFilters()
                    }
                }
            } label: {
                Label("Filter", systemImage: viewModel.positionFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }

            Menu {
                Button {
                    viewModel.exportCSV(from: store)
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                Button {
                    viewModel.exportPDF(from: store)
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
            } label: {
                Label("Export Roster", systemImage: "square.and.arrow.up")
            }
            .disabled(store.roster.isEmpty)

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
        .sheet(item: $viewModel.exportFile, onDismiss: { viewModel.cleanupExport() }) { file in
            RosterShareSheet(url: file.url)
        }
    }

    private var ageGroupBinding: Binding<AgeGroup> {
        Binding {
            store.selectedTeam.ageGroup
        } set: { newValue in
            store.setAgeGroup(newValue, for: store.selectedTeam)
        }
    }

    private var periodFormatBinding: Binding<PeriodFormat> {
        Binding {
            store.selectedTeam.periodFormat
        } set: { newValue in
            store.setPeriodFormat(newValue, for: store.selectedTeam)
        }
    }

    private var minimumMinutesBinding: Binding<Int> {
        Binding {
            store.selectedTeam.defaultMinimumMinutes
        } set: { newValue in
            store.setDefaultMinimumMinutes(newValue, for: store.selectedTeam)
        }
    }
}
