import SwiftUI

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
                case .calendar:
                    CalendarView()
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
