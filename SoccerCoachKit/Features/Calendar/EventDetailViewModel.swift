import Foundation

@MainActor
final class EventDetailViewModel: ObservableObject {
    let eventID: UUID
    @Published var showingEditEvent = false

    init(eventID: UUID) {
        self.eventID = eventID
    }

    func event(in store: AppStore) -> TeamEvent? {
        store.events.first { $0.id == eventID }
    }

    func delete(_ event: TeamEvent, from store: AppStore) {
        store.deleteEvent(event)
    }
}
