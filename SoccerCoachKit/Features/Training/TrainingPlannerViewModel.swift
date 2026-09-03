import Foundation

@MainActor
final class TrainingPlannerViewModel: ObservableObject {
    @Published var showingNewSession = false
    @Published var searchText = ""

    var isSearching: Bool { SearchQuery.isActive(searchText) }

    /// The team's sessions narrowed by the search text. Block topics and focuses
    /// are included: a coach looking for "the one with the rondo" is thinking of
    /// what was in the session, not what they called it.
    func filteredSessions(in store: AppStore) -> [TrainingSession] {
        store.teamSessions.filter { session in
            SearchQuery.matches(searchText, in: [session.title, session.objective]
                + session.blocks.map(\.topic)
                + session.blocks.map(\.focus))
        }
    }

    func delete(_ session: TrainingSession, from store: AppStore) {
        store.deleteSession(session)
    }
}
