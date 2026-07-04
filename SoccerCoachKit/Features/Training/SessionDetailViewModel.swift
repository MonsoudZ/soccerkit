import Foundation

@MainActor
final class SessionDetailViewModel: ObservableObject {
    let sessionID: UUID
    @Published var showingEditSession = false
    @Published var exportFile: SessionExportFile?

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func session(in store: AppStore) -> TrainingSession? {
        store.sessions.first { $0.id == sessionID }
    }

    func delete(_ session: TrainingSession, from store: AppStore) {
        store.deleteSession(session)
    }

    func exportPDF(in store: AppStore) {
        guard let session = session(in: store) else { return }
        if let previous = exportFile?.url {
            try? FileManager.default.removeItem(at: previous)
        }
        let data = SessionExporter.pdfData(for: session, in: store)
        let name = SessionExporter.fileName(for: session)
        guard let url = SessionExporter.write(data, fileName: name) else { return }
        exportFile = SessionExportFile(url: url)
    }

    /// Removes the temp export file once the share sheet is dismissed.
    func cleanupExport() {
        guard let url = exportFile?.url else { return }
        try? FileManager.default.removeItem(at: url)
        exportFile = nil
    }
}
