import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var sidebarSelection: AppSection? = .dashboard

    /// The sections that get their own bottom tab on iPhone; the rest live under
    /// "More". iPad shows every section in the sidebar instead.
    private static let primaryTabs: [AppSection] = [.dashboard, .calendar, .roster, .game]
    private static let moreSections: [AppSection] = [.games, .stats, .field, .training, .drills, .settings]

    var body: some View {
        root
            .undoBanner()
            .onChange(of: scenePhase) { _ in
                if scenePhase == .active {
                    store.refreshEventReminders()
                } else {
                    store.flushPendingWrites()
                }
            }
            .fullScreenCover(isPresented: showOnboarding) {
                OnboardingView { hasOnboarded = true }
            }
    }

    @ViewBuilder
    private var root: some View {
        if sizeClass == .compact {
            tabRoot
        } else {
            splitRoot
        }
    }

    // MARK: iPhone — bottom tab bar

    private var tabRoot: some View {
        TabView {
            ForEach(Self.primaryTabs) { section in
                NavigationStack {
                    AppSectionDetail(section: section)
                        .navigationTitle(section.rawValue)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { TeamMenu() }
                        }
                }
                .tabItem { Label(section.rawValue, systemImage: section.symbol) }
            }

            NavigationStack {
                MoreScreen(sections: Self.moreSections)
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }

    // MARK: iPad — sidebar split

    private var splitRoot: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section { TeamPicker() }
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .tag(section)
                    }
                }
            }
            .themedList()
            .navigationTitle("Coach")
        } detail: {
            // The game-day model lives on AppStore (app-lifetime), so a live
            // match survives section switches even where this column is rebuilt.
            AppSectionDetail(section: sidebarSelection ?? .dashboard)
                .navigationTitle((sidebarSelection ?? .dashboard).rawValue)
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })
    }
}

/// Resolves a section to its screen. Shared by the tab bar, the "More" list, and
/// the iPad sidebar so there's a single place that maps sections to views.
struct AppSectionDetail: View {
    @EnvironmentObject private var store: AppStore
    let section: AppSection

    var body: some View {
        switch section {
        case .dashboard: CoachOverviewView()
        case .calendar: CalendarView()
        case .roster: RosterView()
        case .game: GameDayView(viewModel: store.gameDay)
        case .games: GamesView()
        case .stats: SeasonStatsView()
        case .field: FieldBoardView()
        case .training: TrainingPlannerView()
        case .drills: DrillLibraryView()
        case .settings: SettingsView()
        }
    }
}

/// The "More" tab: team switcher plus the sections that don't get their own tab.
private struct MoreScreen: View {
    let sections: [AppSection]

    var body: some View {
        List {
            Section { TeamPicker() }
            Section {
                ForEach(sections) { section in
                    NavigationLink {
                        AppSectionDetail(section: section)
                            .navigationTitle(section.rawValue)
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("More")
    }
}

/// A compact team switcher for the navigation bar (the sidebar uses the fuller
/// `TeamPicker`).
private struct TeamMenu: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            Picker("Team", selection: $store.selectedTeamID) {
                ForEach(store.teams) { team in
                    Text(team.name).tag(team.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Circle().fill(store.selectedTeam.accentColor).frame(width: 10, height: 10)
                Text(store.selectedTeam.name).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
    }
}
