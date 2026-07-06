import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var auth: AuthController
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            accountSection
            remindersSection
            syncSection
            appearanceSection
            backupSection
            if store.hasCorruptBackup { recoverySection }
            dataSection
            aboutSection
        }
        .themedList()
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

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            LabeledContent("Signed in", value: auth.displayName ?? "Apple ID")
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Account")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $store.eventRemindersEnabled) {
                Label("Event Reminders", systemImage: "bell.badge")
            }
            if store.eventRemindersEnabled {
                Picker(selection: $store.reminderLeadMinutes) {
                    Text("At start").tag(0)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("3 hours before").tag(180)
                    Text("1 day before").tag(1440)
                } label: {
                    Label("Remind me", systemImage: "clock")
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Get a notification before upcoming games, practices, and events.")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle(isOn: $store.cloudSyncEnabled) {
                Label("iCloud Sync", systemImage: "icloud")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Keep your teams, players, games, and plans in sync across your devices using iCloud.")
        }
    }

    private var appearanceSection: some View {
        Section {
            ThemePickerRow(themeManager: themeManager)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose an accent and surface palette. Your choice applies across the app and is remembered.")
        }
    }

    private var backupSection: some View {
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
    }

    private var recoverySection: some View {
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

    private var dataSection: some View {
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
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            NavigationLink {
                StyleGuideView()
            } label: {
                Label("Style Guide", systemImage: "paintpalette")
            }
        }
    }

    // MARK: - Helpers

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
