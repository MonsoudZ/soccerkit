import SwiftUI

struct PlayerFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerFormViewModel

    init(player: Player? = nil) {
        _viewModel = StateObject(wrappedValue: PlayerFormViewModel(player: player))
    }

    var body: some View {
        Form {
            Section("Player") {
                TextField("Name", text: $viewModel.name)
                Stepper("Number \(viewModel.number)", value: $viewModel.number, in: 0...99)
                Picker("Position", selection: $viewModel.position) {
                    ForEach(PlayerPosition.allCases) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
            }

            Section("Parent / Guardian") {
                TextField("Guardian name", text: $viewModel.guardian)
                TextField("Phone", text: $viewModel.guardianPhone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $viewModel.guardianEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section("Secondary Contact") {
                TextField("Name", text: $viewModel.secondaryContactName)
                TextField("Phone", text: $viewModel.secondaryContactPhone)
                    .keyboardType(.phonePad)
            }

            Section("Emergency Contact") {
                TextField("Name", text: $viewModel.emergencyContactName)
                TextField("Phone", text: $viewModel.emergencyContactPhone)
                    .keyboardType(.phonePad)
                TextField("Relationship", text: $viewModel.emergencyContactRelation)
            }

            Section {
                TextField("Allergies", text: $viewModel.allergies, axis: .vertical)
                    .lineLimit(1...3)
                TextEditor(text: $viewModel.medicalNotes)
                    .frame(minHeight: 80)
            } header: {
                Text("Medical")
            } footer: {
                Text("Note allergies, conditions, medications, or anything staff should know in an emergency.")
            }

            Section {
                Toggle("Custom minimum minutes", isOn: $viewModel.overrideMinMinutes)
                if viewModel.overrideMinMinutes {
                    Stepper("Minimum \(viewModel.minMinutes) min", value: $viewModel.minMinutes, in: 0...120)
                }
            } header: {
                Text("Playing Time")
            } footer: {
                Text("Overrides the team's default minimum minutes for this player (e.g. easing back from injury).")
            }

            Section("Coach Notes") {
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Player" : "Add Player")
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
