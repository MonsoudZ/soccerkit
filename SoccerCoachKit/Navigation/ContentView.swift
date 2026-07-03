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

/// The persistent detail root. It owns the game-day model so an in-progress
/// match survives section switches, and — because the sidebar lives in a
/// sibling subtree — a running clock re-renders only this container, not the
/// whole navigation shell.
private struct DetailContainer: View {
    @StateObject private var gameDay = GameDayViewModel()
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
                GameDayView(viewModel: gameDay)
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
        .navigationTitle(selection.rawValue)
    }
}
