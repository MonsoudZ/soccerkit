import Foundation

@MainActor
final class RosterViewModel: ObservableObject {
    @Published var showingAddPlayer = false
    @Published var exportFile: RosterExportFile?
    @Published var searchText = ""
    @Published var positionFilter: PlayerPosition?

    var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || positionFilter != nil
    }

    /// The selected team's roster narrowed by the search text and position filter.
    func filteredRoster(in store: AppStore) -> [Player] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.roster.filter { player in
            let matchesPosition = positionFilter == nil || player.position == positionFilter
            let matchesQuery = query.isEmpty
                || player.name.lowercased().contains(query)
                || player.guardian.lowercased().contains(query)
                || player.position.rawValue.lowercased().contains(query)
                || "\(player.number)".contains(query)
            return matchesPosition && matchesQuery
        }
    }

    func clearFilters() {
        searchText = ""
        positionFilter = nil
    }

    func delete(_ player: Player, from store: AppStore) {
        store.deletePlayer(player)
    }

    func exportCSV(from store: AppStore) {
        let data = RosterExporter.csvData(for: store.roster, team: store.selectedTeam)
        present(data, extension: "csv", team: store.selectedTeam)
    }

    func exportPDF(from store: AppStore) {
        let data = RosterExporter.pdfData(for: store.roster, team: store.selectedTeam)
        present(data, extension: "pdf", team: store.selectedTeam)
    }

    /// Removes the temp export file once the share sheet is dismissed, so
    /// exported files don't accumulate in the temporary directory.
    func cleanupExport() {
        guard let url = exportFile?.url else { return }
        try? FileManager.default.removeItem(at: url)
        exportFile = nil
    }

    private func present(_ data: Data, extension fileExtension: String, team: Team) {
        // Drop any previous export before writing a new one.
        if let previous = exportFile?.url {
            try? FileManager.default.removeItem(at: previous)
        }
        let name = RosterExporter.fileName(for: team, extension: fileExtension)
        guard let url = RosterExporter.write(data, fileName: name) else { return }
        exportFile = RosterExportFile(url: url)
    }
}
