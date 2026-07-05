import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var auth: AuthController
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
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

            Section {
                ThemePickerRow(themeManager: themeManager)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose an accent and surface palette. Your choice applies across the app and is remembered.")
            }

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
                NavigationLink {
                    StyleGuideView()
                } label: {
                    Label("Style Guide", systemImage: "paintpalette")
                }
            }
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

/// A horizontal row of theme swatches; tapping one switches the app theme live.
struct ThemePickerRow: View {
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Theme.all) { theme in
                let isSelected = theme.id == themeManager.selectedID
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        themeManager.select(theme)
                    }
                } label: {
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(theme.brand)
                                .frame(width: 40, height: 40)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? theme.brand : Color.hairline,
                                lineWidth: isSelected ? 2.5 : 1
                            )
                            .frame(width: 48, height: 48)
                        )
                        .frame(width: 48, height: 48)

                        Text(theme.name)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
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
