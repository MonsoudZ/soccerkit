import Foundation

@MainActor
final class DrillDetailViewModel: ObservableObject {
    let drillID: UUID
    @Published var showingEditDrill = false

    init(drillID: UUID) {
        self.drillID = drillID
    }

    func drill(in store: AppStore) -> Drill? {
        store.drills.first { $0.id == drillID }
    }

    func delete(_ drill: Drill, from store: AppStore) {
        store.deleteDrill(drill)
    }
}
