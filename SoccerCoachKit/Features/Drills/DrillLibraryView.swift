import SwiftUI

struct DrillLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = DrillLibraryViewModel()

    var body: some View {
        let visibleTags = viewModel.visibleTags(in: store)
        let filteredDrills = viewModel.filteredDrills(in: store)

        List {
            Section {
                Picker("Library", selection: $viewModel.scope) {
                    ForEach(DrillLibraryScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Category", selection: $viewModel.category) {
                    Text("All").tag(DrillCategory?.none)
                    ForEach(DrillCategory.allCases) { item in
                        Text(item.rawValue).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)

                if !visibleTags.isEmpty {
                    Picker("Tag", selection: $viewModel.selectedTag) {
                        Text("All Tags").tag(String?.none)
                        ForEach(visibleTags, id: \.self) { tag in
                            Text(tag).tag(Optional(tag))
                        }
                    }
                }
            }

            if filteredDrills.isEmpty {
                InlineEmptyView(
                    title: "No Drills Found",
                    systemImage: "sportscourt",
                    message: "No drills match the current library, category, or tag filters."
                )
            } else {
                ForEach(filteredDrills) { drill in
                    NavigationLink {
                        DrillDetailView(drillID: drill.id)
                    } label: {
                        DrillCard(drill: drill)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(drill, from: store)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .onChange(of: viewModel.scope) { _ in
            viewModel.normalizeTagSelection(in: store)
        }
        .onChange(of: viewModel.selectedTag) { _ in
            viewModel.normalizeTagSelection(in: store)
        }
        .listStyle(.insetGrouped)
        .themedList()
        .navigationTitle("Drills")
        .toolbar {
            Button {
                viewModel.showingNewDrill = true
            } label: {
                Label("Add Drill", systemImage: "plus")
            }
        }
        .sheet(isPresented: $viewModel.showingNewDrill) {
            NavigationStack {
                DrillFormView()
            }
        }
    }
}
