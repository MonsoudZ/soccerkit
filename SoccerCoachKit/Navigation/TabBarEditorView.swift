import SwiftUI

/// Lets the coach curate the Quick Access tab bar: add, remove, and reorder the
/// sections shown next to Home. Home is pinned and always present.
struct TabBarEditorView: View {
    @EnvironmentObject private var prefs: TabPreferences

    var body: some View {
        List {
            Section {
                row(.dashboard, trailing: {
                    Label("Pinned", systemImage: "pin.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                })
            } header: {
                Text("Always Shown")
            } footer: {
                Text("Home is always the first tab.")
            }

            Section {
                if prefs.favorites.isEmpty {
                    Text("No quick-access tabs yet. Add sections from More below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.favorites) { section in
                        row(section)
                    }
                    .onMove { prefs.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { prefs.remove(atOffsets: $0) }
                }
            } header: {
                HStack {
                    Text("Quick Access")
                    Spacer()
                    Text("\(prefs.favorites.count)/\(TabPreferences.maxFavorites)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("These appear as tabs beside Home. Tap Edit to reorder or remove.")
            }

            Section {
                ForEach(prefs.available) { section in
                    Button {
                        prefs.add(section)
                    } label: {
                        HStack {
                            sectionLabel(section)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(prefs.isFull ? Color.secondary : Color.positive)
                        }
                    }
                    .disabled(prefs.isFull)
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("More")
            } footer: {
                if prefs.isFull {
                    Text("Quick Access is full. Remove a tab above to add one of these.")
                }
            }
        }
        .themedList()
        .navigationTitle("Customize Tabs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset") { prefs.resetToDefault() }
            }
        }
    }

    private func sectionLabel(_ section: AppSection) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            IconChip(symbol: section.symbol, accent: .brand, size: 28)
        }
    }

    @ViewBuilder
    private func row(_ section: AppSection, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack {
            sectionLabel(section)
            Spacer()
            trailing()
        }
    }
}
