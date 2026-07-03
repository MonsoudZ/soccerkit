import Foundation

@MainActor
final class SessionDetailViewModel: ObservableObject {
    let sessionID: UUID
    @Published var showingEditSession = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func session(in store: AppStore) -> TrainingSession? {
        store.sessions.first { $0.id == sessionID }
    }

    func delete(_ session: TrainingSession, from store: AppStore) {
        store.deleteSession(session)
    }
}
