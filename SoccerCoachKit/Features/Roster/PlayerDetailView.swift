import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerDetailViewModel

    init(playerID: UUID) {
        _viewModel = StateObject(wrappedValue: PlayerDetailViewModel(playerID: playerID))
    }

    var body: some View {
        Group {
            if let player = viewModel.player(in: store) {
                Form {
                    Section("Player") {
                        LabeledContent("Name", value: player.name)
                        LabeledContent("Number", value: "#\(player.number)")
                        LabeledContent("Position", value: player.position.rawValue)
                    }

                    // The player's team comes from their active membership now
                    // that the flat teamID is gone; their games scope the season
                    // profile and readiness insight.
                    let teamGames = store.teamID(ofPlayer: player.id).map { store.games(inTeam: $0) } ?? []
                    PlayerDevelopmentSection(
                        profile: PlayerDevelopment.profile(for: player, games: teamGames)
                    )

                    PlayerReadinessSection(
                        insight: MatchInsights.insight(for: player.id, games: teamGames)
                    )

                    let evaluations = store.athleteEvaluations(player)
                    EvaluationTrendSection(
                        readiness: EvaluationReadModel.readinessTrend(evaluations),
                        averageReadiness: EvaluationReadModel.averageReadiness(evaluations),
                        effort: EvaluationReadModel.effortTrend(evaluations)
                    )

                    Section("Parent / Guardian") {
                        LabeledContent("Guardian", value: player.guardian.isEmpty ? "—" : player.guardian)
                        ContactRow(label: "Phone", value: player.guardianPhone, kind: .phone)
                        ContactRow(label: "Email", value: player.guardianEmail, kind: .email)
                    }

                    if !player.secondaryContactName.isEmpty || !player.secondaryContactPhone.isEmpty {
                        Section("Secondary Contact") {
                            if !player.secondaryContactName.isEmpty {
                                LabeledContent("Name", value: player.secondaryContactName)
                            }
                            ContactRow(label: "Phone", value: player.secondaryContactPhone, kind: .phone)
                        }
                    }

                    Section("Emergency Contact") {
                        if player.emergencyContactName.isEmpty && player.emergencyContactPhone.isEmpty {
                            Text("No emergency contact on file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if !player.emergencyContactName.isEmpty {
                                LabeledContent("Name", value: player.emergencyContactName)
                            }
                            ContactRow(label: "Phone", value: player.emergencyContactPhone, kind: .phone)
                            if !player.emergencyContactRelation.isEmpty {
                                LabeledContent("Relationship", value: player.emergencyContactRelation)
                            }
                        }
                    }

                    Section("Medical") {
                        if player.allergies.isEmpty && player.medicalNotes.isEmpty {
                            Text("No medical notes on file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if !player.allergies.isEmpty {
                                LabeledContent("Allergies") {
                                    Text(player.allergies)
                                        .foregroundStyle(.red)
                                }
                            }
                            if !player.medicalNotes.isEmpty {
                                Text(player.medicalNotes)
                            }
                        }
                    }

                    Section("Coach Notes") {
                        Text(player.notes.isEmpty ? "—" : player.notes)
                    }

                    Section {
                        let entries = player.developmentLog.sorted { $0.date > $1.date }
                        if entries.isEmpty {
                            Text("No development entries yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(entries) { entry in
                                Button {
                                    viewModel.editingEntry = entry
                                } label: {
                                    DevelopmentEntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.deleteDevelopmentEntry(entry, for: player)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        Button {
                            viewModel.showingNewEntry = true
                        } label: {
                            Label("Add Development Entry", systemImage: "chart.line.uptrend.xyaxis")
                        }
                    } header: {
                        Text("Development")
                    }

                    Section {
                        let instances = store.formInstances(for: .athlete(player.id))
                        if instances.isEmpty {
                            Text("No evaluations recorded through the form engine yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(instances) { instance in
                                Button {
                                    viewModel.editingInstance = instance
                                } label: {
                                    FormInstanceRow(instance: instance, template: store.template(for: instance))
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.deleteFormInstance(instance)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        Menu {
                            ForEach(store.allFormTemplates.filter { $0.subjectType == .athlete }) { template in
                                Button(template.name) { viewModel.recordingTemplate = template }
                            }
                        } label: {
                            Label("Record Evaluation", systemImage: "square.and.pencil")
                        }
                    } header: {
                        Text("Evaluations")
                    } footer: {
                        Text("Powered by the shared evaluation engine — the same form spine behind check-ins, tryouts, and development.")
                    }
                }
                .themedList()
            } else {
                EmptyStateView(title: "Player Removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(viewModel.player(in: store)?.name ?? "Player")
        .toolbar {
            if let player = viewModel.player(in: store) {
                Button {
                    viewModel.showingEditPlayer = true
                } label: {
                    Label("Edit Player", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.delete(player, from: store)
                    dismiss()
                } label: {
                    Label("Delete Player", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditPlayer) {
            if let player = viewModel.player(in: store) {
                NavigationStack {
                    PlayerFormView(player: player)
                }
            }
        }
        .sheet(isPresented: $viewModel.showingNewEntry) {
            NavigationStack {
                DevelopmentEntryFormView(playerID: viewModel.playerID)
            }
        }
        .sheet(item: $viewModel.editingEntry) { entry in
            NavigationStack {
                DevelopmentEntryFormView(playerID: viewModel.playerID, entry: entry)
            }
        }
        .sheet(item: $viewModel.recordingTemplate) { template in
            NavigationStack {
                FormRunnerView(template: template, subject: .athlete(viewModel.playerID))
            }
        }
        .sheet(item: $viewModel.editingInstance) { instance in
            NavigationStack {
                if let template = store.template(for: instance) {
                    FormRunnerView(template: template, subject: instance.subject,
                                   contextRef: instance.contextRef, existing: instance)
                }
            }
        }
    }
}
