import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var showingNewTeam = false
    @Published var showingEditTeam = false
    @Published var showingDeleteTeam = false
}
