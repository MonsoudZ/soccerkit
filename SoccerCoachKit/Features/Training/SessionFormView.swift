import SwiftUI

struct SessionFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SessionFormViewModel

    init(session: TrainingSession? = nil, initialDate: Date? = nil) {
        _viewModel = StateObject(wrappedValue: SessionFormViewModel(session: session, initialDate: initialDate))
    }

    var body: some View {
        Form {
            Section("Session") {
                TextField("Title", text: $viewModel.title)
                DatePicker("Date", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                TextField("Weather", text: $viewModel.weather)
                LabeledContent("Team", value: store.selectedTeam.name)
                LabeledContent("Time of Day", value: viewModel.date.formatted(date: .omitted, time: .shortened))
            }

            Section("Session Description") {
                TextEditor(text: $viewModel.objective)
                    .frame(minHeight: 120)
            }

            Section {
                if store.teamDrills.isEmpty {
                    Text("Add team or shared drills before building this session plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Drill", selection: $viewModel.selectedDrillID) {
                        ForEach(store.teamDrills) { drill in
                            Text(drill.title).tag(Optional(drill.id))
                        }
                    }
                    .onChange(of: viewModel.selectedDrillID) { _ in
                        viewModel.handleDrillSelectionChange(in: store)
                    }

                    let selectedDrillDiagrams = viewModel.selectedDrillDiagrams(in: store)
                    if !selectedDrillDiagrams.isEmpty {
                        Picker("Field Diagram", selection: $viewModel.selectedDiagramID) {
                            Text("None").tag(UUID?.none)
                            ForEach(selectedDrillDiagrams) { diagram in
                                Text(diagram.title).tag(Optional(diagram.id))
                            }
                        }
                    } else if viewModel.selectedDrillID != nil {
                        Text("No field diagrams attached to this drill yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Section topic", text: $viewModel.newBlockTopic, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Part of pitch", text: $viewModel.newBlockPitchArea)
                    Stepper("\(viewModel.newBlockMinutes) minutes", value: $viewModel.newBlockMinutes, in: 1...90)
                    Stepper("Intensity \(viewModel.newBlockIntensity) / 5", value: $viewModel.newBlockIntensity, in: 1...5)
                    TextField("Coaching focus", text: $viewModel.newBlockFocus, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Section description", text: $viewModel.newBlockDetails, axis: .vertical)
                        .lineLimit(2...5)

                    DisclosureGroup("Positions") {
                        ForEach(PlayerPosition.allCases) { position in
                            Toggle(position.rawValue, isOn: positionBinding(for: position))
                        }
                    }

                    Button {
                        viewModel.addSelectedDrillBlock(in: store)
                    } label: {
                        Label(viewModel.blocks.count >= 6 ? "Maximum 6 Sections" : "Add Section to Plan", systemImage: "plus.circle")
                    }
                    .disabled(viewModel.selectedDrillID == nil || viewModel.blocks.count >= 6)
                }
            } header: {
                Text("Build Sections From Drills")
            } footer: {
                Text("\(viewModel.blocks.count) / 6 sections, \(viewModel.planMinutes) total minutes")
            }

            if !viewModel.blocks.isEmpty {
                Section {
                    ForEach($viewModel.blocks) { $block in
                        SessionBlockEditorRow(
                            block: $block,
                            drill: store.drill(for: block.drillID),
                            diagrams: viewModel.diagrams(for: block, in: store)
                        )
                    }
                    .onDelete { offsets in
                        viewModel.blocks.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        viewModel.blocks.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Session Plan")
                } footer: {
                    Text("Total practice time: \(viewModel.planMinutes) minutes")
                }
            }
        }
        .onAppear { viewModel.prepareDefaultDrillSelection(in: store) }
        .navigationTitle(viewModel.isEditing ? "Edit Session" : "New Session")
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

            if !viewModel.blocks.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    EditButton()
                }
            }
        }
    }

    private func positionBinding(for position: PlayerPosition) -> Binding<Bool> {
        Binding {
            viewModel.selectedPositions.contains(position)
        } set: { isSelected in
            if isSelected {
                viewModel.selectedPositions.insert(position)
            } else {
                viewModel.selectedPositions.remove(position)
            }
        }
    }
}
