import Foundation

@MainActor
final class EventFormViewModel: ObservableObject {
    let event: TeamEvent?
    @Published var title: String
    @Published var kind: TeamEventKind
    @Published var date: Date
    @Published var isMultiDay: Bool
    @Published var endDate: Date
    @Published var location: String
    @Published var notes: String

    init(event: TeamEvent?, initialDate: Date?) {
        self.event = event
        title = event?.title ?? ""
        kind = event?.kind ?? .tournament
        let start = event?.date ?? initialDate ?? Date()
        date = start
        isMultiDay = event?.endDate != nil
        endDate = event?.endDate ?? start
        location = event?.location ?? ""
        notes = event?.notes ?? ""
    }

    var isEditing: Bool { event != nil }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(into store: AppStore) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEnd: Date? = isMultiDay ? max(endDate, date) : nil

        if let event {
            var updated = event
            updated.title = cleanTitle
            updated.kind = kind
            updated.date = date
            updated.endDate = resolvedEnd
            updated.location = cleanLocation
            updated.notes = cleanNotes
            store.updateEvent(updated)
        } else {
            store.addEvent(
                title: cleanTitle,
                kind: kind,
                date: date,
                endDate: resolvedEnd,
                location: cleanLocation,
                notes: cleanNotes
            )
        }
    }
}
