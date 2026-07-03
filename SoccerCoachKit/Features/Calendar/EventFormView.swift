import SwiftUI

struct EventFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EventFormViewModel

    init(event: TeamEvent? = nil, initialDate: Date? = nil) {
        _viewModel = StateObject(wrappedValue: EventFormViewModel(event: event, initialDate: initialDate))
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $viewModel.title)
                Picker("Type", selection: $viewModel.kind) {
                    ForEach(TeamEventKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                DatePicker("Starts", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                Toggle("Multi-day event", isOn: $viewModel.isMultiDay)
                if viewModel.isMultiDay {
                    DatePicker("Ends", selection: $viewModel.endDate, in: viewModel.date..., displayedComponents: [.date])
                }
                TextField("Location", text: $viewModel.location)
                LabeledContent("Team", value: store.selectedTeam.name)
            }

            Section("Notes") {
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Event" : "New Event")
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
