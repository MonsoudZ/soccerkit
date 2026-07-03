import Foundation

enum DrillLibraryScope: String, CaseIterable, Identifiable {
    case team = "Team"
    case shared = "Shared"
    case all = "All"

    var id: String { rawValue }
}

@MainActor
final class DrillLibraryViewModel: ObservableObject {
    @Published var category: DrillCategory?
    @Published var scope: DrillLibraryScope = .team
    @Published var selectedTag: String?
    @Published var showingNewDrill = false

    func visibleDrills(in store: AppStore) -> [Drill] {
        switch scope {
        case .team:
            return store.teamDrills
        case .shared:
            return store.drills.filter { !$0.isArchived && $0.teamID == nil }.sorted { $0.title < $1.title }
        case .all:
            return store.drills.filter { !$0.isArchived }.sorted { $0.title < $1.title }
        }
    }

    func visibleTags(in store: AppStore) -> [String] {
        Array(Set(visibleDrills(in: store).flatMap(\.tags))).sorted()
    }

    func filteredDrills(in store: AppStore) -> [Drill] {
        visibleDrills(in: store)
            .filter { drill in
                category == nil || drill.category == category
            }
            .filter { drill in
                guard let selectedTag else { return true }
                return drill.tags.contains(selectedTag)
            }
    }

    /// Clears the tag filter when it no longer exists in the current scope.
    func normalizeTagSelection(in store: AppStore) {
        if let selectedTag, !visibleTags(in: store).contains(selectedTag) {
            self.selectedTag = nil
        }
    }

    func delete(_ drill: Drill, from store: AppStore) {
        store.deleteDrill(drill)
    }
}
