import SwiftUI

struct TeamFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TeamFormViewModel

    init(team: Team? = nil) {
        _viewModel = StateObject(wrappedValue: TeamFormViewModel(team: team))
    }

    var body: some View {
        Form {
            Section("Team") {
                TextField("Team name", text: $viewModel.name)
                Picker("Age Group", selection: $viewModel.ageGroup) {
                    ForEach(AgeGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                TextField("Season", text: $viewModel.season)
                TextField("Accent", text: $viewModel.accentName)
            }

            Section("Rules") {
                LabeledContent("Roster Limit", value: "\(viewModel.ageGroup.maxRosterSize)")
                LabeledContent("Game Format", value: "\(viewModel.ageGroup.playersOnField)v\(viewModel.ageGroup.playersOnField)")
                LabeledContent("Default Game", value: "\(viewModel.ageGroup.defaultGameMinutes) min")
            }

            Section("Training Board Defaults") {
                Stepper("Players \(viewModel.defaultPlayerCount)", value: $viewModel.defaultPlayerCount, in: 0...22)
                Stepper("Opposition \(viewModel.defaultOpponentCount)", value: $viewModel.defaultOpponentCount, in: 0...22)
                Stepper("Cones \(viewModel.defaultConeCount)", value: $viewModel.defaultConeCount, in: 0...40)
                Stepper("Zones \(viewModel.defaultZoneCount)", value: $viewModel.defaultZoneCount, in: 0...8)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Team" : "New Team")
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
