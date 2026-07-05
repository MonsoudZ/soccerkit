import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var exportFile: SettingsExportFile?
    @Published var showingImporter = false
    @Published var showingResetConfirm = false
    @Published var showingDiscardConfirm = false
    @Published var alertText: String?

    func exportBackup(from store: AppStore) {
        guard let data = store.exportData() else {
            alertText = "Couldn't create a backup."
            return
        }
        share(data, name: "SoccerCoachKit-backup.json")
    }

    func exportCorruptBackup(from store: AppStore) {
        guard let data = store.corruptBackupData() else { return }
        share(data, name: "SoccerCoachKit-unreadable-data.json")
    }

    func importBackup(_ result: Result<URL, Error>, into store: AppStore) {
        switch result {
        case .failure:
            alertText = "Couldn't open that file."
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), store.importData(data) else {
                alertText = "That file isn't a valid SoccerCoachKit backup."
                return
            }
            alertText = "Backup restored."
        }
    }

    /// Removes the temp export file once the share sheet is dismissed.
    func cleanupExport() {
        if let url = exportFile?.url { try? FileManager.default.removeItem(at: url) }
        exportFile = nil
    }

    private func share(_ data: Data, name: String) {
        if let previous = exportFile?.url { try? FileManager.default.removeItem(at: previous) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            exportFile = SettingsExportFile(url: url)
        } catch {
            alertText = "Couldn't write the backup file."
        }
    }
}

/// Identifiable wrapper so a prepared export URL can drive a `.sheet(item:)`.
struct SettingsExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
