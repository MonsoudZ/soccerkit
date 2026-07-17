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
        .confirmationDialog("Delete your account?", isPresented: $viewModel.showingDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await viewModel.deleteAccount(store: store, auth: auth) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all your data — teams, players, evaluations, and everything synced — everywhere. This can't be undone.")
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
            Button {
                viewModel.exportMyData(from: store)
            } label: {
                SettingsLabel(title: "Export My Data", systemImage: "square.and.arrow.up", tint: .info)
            }
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                SettingsLabel(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", tint: .critical)
            }
            Button(role: .destructive) {
                viewModel.showingDeleteAccountConfirm = true
            } label: {
                SettingsLabel(title: "Delete Account", systemImage: "trash", tint: .critical)
            }
            .disabled(viewModel.isDeletingAccount)
        } header: {
            Text("Account")
        } footer: {
            Text("Deleting your account permanently removes all your data everywhere. Export a copy first if you want to keep it.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $store.eventRemindersEnabled) {
                SettingsLabel(title: "Event Reminders", systemImage: "bell.badge", tint: .caution)
            }
            if store.eventRemindersEnabled {
                Picker(selection: $store.reminderLeadMinutes) {
                    Text("At start").tag(0)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("3 hours before").tag(180)
                    Text("1 day before").tag(1440)
                } label: {
                    SettingsLabel(title: "Remind me", systemImage: "clock", tint: .info)
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
                SettingsLabel(title: "iCloud Sync", systemImage: "icloud", tint: .info)
            }

            if store.cloudSyncEnabled {
                LabeledContent {
                    Label(store.syncStatus.label, systemImage: store.syncStatus.systemImage)
                        .foregroundStyle(store.syncStatus.tint)
                        .font(.subheadline.weight(.medium))
                } label: {
                    Text("Status")
                }

                if let detail = store.syncStatus.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.syncStatus.isFailed || store.syncStatus == .unavailable {
                    Button {
                        store.retrySync()
                    } label: {
                        Label("Retry Sync", systemImage: "arrow.clockwise")
                    }
                }
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
                SettingsLabel(title: "Export Backup", systemImage: "square.and.arrow.up", tint: .positive)
            }
            Button {
                viewModel.showingImporter = true
            } label: {
                SettingsLabel(title: "Restore from Backup", systemImage: "square.and.arrow.down", tint: .info)
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
                SettingsLabel(title: "Export Unreadable Data", systemImage: "arrow.up.doc", tint: .caution)
            }
            Button(role: .destructive) {
                viewModel.showingDiscardConfirm = true
            } label: {
                SettingsLabel(title: "Discard", systemImage: "trash", tint: .critical)
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
                SettingsLabel(title: "Reset to Sample Data", systemImage: "arrow.counterclockwise", tint: .critical)
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
            #if DEBUG
            // Developer-only design-system reference; not shipped in release.
            NavigationLink {
                StyleGuideView()
            } label: {
                SettingsLabel(title: "Style Guide", systemImage: "paintpalette", tint: .brand)
            }
            #endif
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
