import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            Section {
                Button {
                    viewModel.exportBackup(from: store)
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                Button {
                    viewModel.showingImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export saves all teams, players, games, sessions, drills, and diagrams as a JSON file you can keep or move to another device. Restoring replaces everything with the file's contents.")
            }

            if store.hasCorruptBackup {
                Section {
                    Button {
                        viewModel.exportCorruptBackup(from: store)
                    } label: {
                        Label("Export Unreadable Data", systemImage: "arrow.up.doc")
                    }
                    Button(role: .destructive) {
                        viewModel.showingDiscardConfirm = true
                    } label: {
                        Label("Discard", systemImage: "trash")
                    }
                } header: {
                    Text("Recovery")
                } footer: {
                    Text("A previous save couldn't be read and was set aside so it wasn't overwritten. Export it to attempt recovery, or discard it.")
                }
            }

            Section {
                Button(role: .destructive) {
                    viewModel.showingResetConfirm = true
                } label: {
                    Label("Reset to Sample Data", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Replaces all of your data with the built-in sample team. This can't be undone.")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $viewModel.showingImporter, allowedContentTypes: [.json]) { result in
            viewModel.importBackup(result, into: store)
        }
        .sheet(item: $viewModel.exportFile, onDismiss: { viewModel.cleanupExport() }) { file in
            SettingsShareSheet(url: file.url)
        }
        .confirmationDialog("Reset to sample data?", isPresented: $viewModel.showingResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetToSampleData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently replaces all of your data with the sample team.")
        }
        .confirmationDialog("Discard unreadable data?", isPresented: $viewModel.showingDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.clearCorruptBackup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The set-aside backup will be permanently removed.")
        }
        .alert("Settings", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertText ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertText != nil },
            set: { if !$0 { viewModel.alertText = nil } }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Presents the system share sheet for an exported backup file.
struct SettingsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
