import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case roster = "Roster"
    case game = "Game Day"
    case games = "Games"
    case field = "Field"
    case training = "Training"
    case drills = "Drills"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .roster: return "person.3"
        case .game: return "stopwatch"
        case .games: return "soccerball"
        case .field: return "rectangle.dashed"
        case .training: return "calendar.badge.clock"
        case .drills: return "sportscourt"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    TeamPicker()
                }

                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .tag(section)
                    }
                }
            }
            .navigationTitle("Coach")
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    DashboardView()
                case .roster:
                    RosterView()
                case .game:
                    GameDayView()
                case .games:
                    GamesView()
                case .field:
                    FieldBoardView()
                case .training:
                    TrainingPlannerView()
                case .drills:
                    DrillLibraryView()
                }
            }
            .navigationTitle(selection?.rawValue ?? AppSection.dashboard.rawValue)
        }
    }
}

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
