import SwiftUI

struct GameFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameFormViewModel

    init(game: GameEvent? = nil, initialDate: Date? = nil) {
        _viewModel = StateObject(wrappedValue: GameFormViewModel(game: game, initialDate: initialDate))
    }

    var body: some View {
        Form {
            Section("Game") {
                TextField("Opponent", text: $viewModel.opponent)
                DatePicker("Date", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                Picker("Venue", selection: $viewModel.isHome) {
                    Text("Home").tag(true)
                    Text("Away").tag(false)
                }
                .pickerStyle(.segmented)
                TextField("Location", text: $viewModel.location)
                LabeledContent("Team", value: store.selectedTeam.name)
            }

            Section("Notes") {
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Game" : "New Game")
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
