import Foundation

@MainActor
final class TrainingPlannerViewModel: ObservableObject {
    @Published var showingNewSession = false

    func delete(_ session: TrainingSession, from store: AppStore) {
        store.deleteSession(session)
    }
}
