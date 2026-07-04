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
            DetailContainer(selection: selection ?? .dashboard)
        }
    }
}

/// The detail root. The game-day model lives on `AppStore` (app-lifetime), so a
/// live match survives section switches on every device — including the iPhone,
/// where this container is torn down when navigating back to the sidebar. This
/// view reads (not observes) `store.gameDay`, so the per-second clock re-renders
/// only `GameDayView`, never the navigation shell.
private struct DetailContainer: View {
    @EnvironmentObject private var store: AppStore
    let selection: AppSection

    var body: some View {
        Group {
            switch selection {
            case .dashboard:
                DashboardView()
            case .calendar:
                CalendarView()
            case .roster:
                RosterView()
            case .game:
                GameDayView(viewModel: store.gameDay)
            case .games:
                GamesView()
            case .stats:
                SeasonStatsView()
            case .field:
                FieldBoardView()
            case .training:
                TrainingPlannerView()
            case .drills:
                DrillLibraryView()
            }
        }
        .navigationTitle(selection.rawValue)
    }
}
