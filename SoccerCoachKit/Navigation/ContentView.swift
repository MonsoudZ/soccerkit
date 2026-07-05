import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _ in
            // Persist the latest state durably before the app suspends.
            if scenePhase != .active { store.flushPendingWrites() }
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
                CoachOverviewView()
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
            case .settings:
                SettingsView()
            }
        }
        .navigationTitle(selection.rawValue)
    }
}
