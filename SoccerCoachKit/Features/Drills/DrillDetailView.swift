import SwiftUI

struct DrillDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DrillDetailViewModel

    init(drillID: UUID) {
        _viewModel = StateObject(wrappedValue: DrillDetailViewModel(drillID: drillID))
    }

    var body: some View {
        Group {
            if let drill = viewModel.drill(in: store) {
                Form {
                    Section("Drill") {
                        LabeledContent("Library", value: store.teamName(for: drill.teamID))
                        LabeledContent("Category", value: drill.category.rawValue)
                        LabeledContent("Duration", value: "\(drill.durationMinutes) min")
                        if !drill.fieldSize.isEmpty {
                            LabeledContent("Field Size", value: drill.fieldSize)
                        }
                        if !drill.tags.isEmpty {
                            TagChipsView(tags: drill.tags)
                        }
                    }

                    Section("Setup") {
                        Text(drill.fieldSetup)
                    }

                    Section("Field Diagrams") {
                        let diagrams = store.diagrams(for: drill)
                        if diagrams.isEmpty {
                            Text("No diagrams attached to this drill.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(diagrams) { diagram in
                                NavigationLink {
                                    DiagramPreviewView(diagramID: diagram.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(diagram.title)
                                            .font(.headline)
                                        Text("Updated \(diagram.updatedAt, style: .date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    DrillDetailListSection(title: "Equipment Needed", items: drill.equipment, symbol: "cone")

                    Section("Coaching Points") {
                        ForEach(Array(drill.coachingPoints.enumerated()), id: \.offset) { _, point in
                            Label(point, systemImage: "checkmark.circle")
                        }
                    }

                    DrillDetailListSection(title: "Progression", items: drill.progressions, symbol: "arrow.up.forward.circle")
                    DrillDetailListSection(title: "Regression", items: drill.regressions, symbol: "arrow.down.backward.circle")
                }
            } else {
                EmptyStateView(title: "Drill Removed", systemImage: "sportscourt")
            }
        }
        .navigationTitle(viewModel.drill(in: store)?.title ?? "Drill")
        .toolbar {
            if let drill = viewModel.drill(in: store) {
                Button {
                    viewModel.showingEditDrill = true
                } label: {
                    Label("Edit Drill", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.delete(drill, from: store)
                    dismiss()
                } label: {
                    Label("Delete Drill", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditDrill) {
            if let drill = viewModel.drill(in: store) {
                NavigationStack {
                    DrillFormView(drill: drill)
                }
            }
        }
    }
}

struct DrillDetailListSection: View {
    let title: String
    let items: [String]
    let symbol: String

    var body: some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: symbol)
                }
            }
        }
    }
}
