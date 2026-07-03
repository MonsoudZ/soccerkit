import Foundation

@MainActor
final class RosterViewModel: ObservableObject {
    @Published var showingAddPlayer = false
    @Published var exportFile: RosterExportFile?

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

    private func present(_ data: Data, extension fileExtension: String, team: Team) {
        let name = RosterExporter.fileName(for: team, extension: fileExtension)
        guard let url = RosterExporter.write(data, fileName: name) else { return }
        exportFile = RosterExportFile(url: url)
    }
}
