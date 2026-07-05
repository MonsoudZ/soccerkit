import SwiftUI

struct DrillFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DrillFormViewModel

    init(drill: Drill? = nil) {
        _viewModel = StateObject(wrappedValue: DrillFormViewModel(drill: drill))
    }

    var body: some View {
        Form {
            Section("Drill") {
                TextField("Title", text: $viewModel.title)
                Picker("Team", selection: $viewModel.teamID) {
                    Text("Shared Library").tag(UUID?.none)
                    ForEach(store.teams) { team in
                        Text(team.name).tag(Optional(team.id))
                    }
                }
                Picker("Category", selection: $viewModel.category) {
                    ForEach(DrillCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                Stepper("\(viewModel.durationMinutes) minutes", value: $viewModel.durationMinutes, in: 1...90)
                TextField("Tags", text: $viewModel.tagsText)
                    .textInputAutocapitalization(.never)
            }

            Section("Setup") {
                TextField("Field size", text: $viewModel.fieldSize)
                TextEditor(text: $viewModel.fieldSetup)
                    .frame(minHeight: 90)
            }

            Section("Equipment Needed") {
                TextEditor(text: $viewModel.equipmentText)
                    .frame(minHeight: 90)
            }

            Section("Coaching Points") {
                TextEditor(text: $viewModel.coachingPointsText)
                    .frame(minHeight: 120)
            }

            Section("Progression") {
                TextEditor(text: $viewModel.progressionsText)
                    .frame(minHeight: 100)
            }

            Section("Regression") {
                TextEditor(text: $viewModel.regressionsText)
                    .frame(minHeight: 100)
            }
        }
        .onAppear { viewModel.prepareDefaultTeam(in: store) }
        .themedList()
        .navigationTitle(viewModel.isEditing ? "Edit Drill" : "New Drill")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(into: store)
                    dismiss()
                }
                .disabled(!viewModel.isValid)
            }
        }
    }
}
