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
                }
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
    }
}
