import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SessionDetailViewModel

    init(sessionID: UUID) {
        _viewModel = StateObject(wrappedValue: SessionDetailViewModel(sessionID: sessionID))
    }

    var body: some View {
        Group {
            if let session = viewModel.session(in: store) {
                List {
                    Section("Session") {
                        LabeledContent("Team", value: store.teamName(for: session.teamID))
                        LabeledContent("Weather", value: session.weather)
                        LabeledContent("Time", value: session.date.formatted(date: .omitted, time: .shortened))
                        LabeledContent("Total Time", value: "\(session.blocks.reduce(0) { $0 + $1.minutes }) min")
                    }

                    Section("Description") {
                        Text(session.objective)
                            .font(.body)
                    }

                    Section("Plan") {
                        if session.blocks.isEmpty {
                            Text("No drills planned yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.blocks) { block in
                                if let drill = store.drill(for: block.drillID) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("\(block.minutes) min", systemImage: "timer")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Label("\(block.intensity) / 5", systemImage: "flame")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(drill.category.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.thinMaterial)
                                                .clipShape(Capsule())
                                        }

                                        Text(block.topic.isEmpty ? drill.title : block.topic)
                                            .font(.headline)

                                        Text(drill.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if !block.pitchArea.isEmpty {
                                            Label(block.pitchArea, systemImage: "rectangle.dashed")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if !block.positions.isEmpty {
                                            Text("Positions: \(block.positions.map(\.rawValue).joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(block.focus)
                                            .foregroundStyle(.secondary)

                                        if !block.details.isEmpty {
                                            Text(block.details)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let diagram = store.diagram(for: block.diagramID) {
                                            NavigationLink {
                                                DiagramPreviewView(diagramID: diagram.id)
                                            } label: {
                                                Label(diagram.title, systemImage: "sportscourt")
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    Section("Field Diagrams") {
                        let diagrams = store.diagrams(for: session)
                        if diagrams.isEmpty {
                            Text("No diagrams attached.")
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

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: session.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: session)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(session.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }

                    Section {
                        ForEach(store.roster) { player in
                            AttendanceRow(player: player, status: session.attendance[player.id] ?? .absent) { status in
                                store.setAttendance(status, for: player, in: session)
                            }
                        }
                    } header: {
                        Text("Attendance")
                    } footer: {
                        let summary = store.attendanceSummary(for: session)
                        Text("\(summary.present) of \(summary.total) present")
                    }
                }
            } else {
                EmptyStateView(title: "Session Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(viewModel.session(in: store)?.title ?? "Session")
        .toolbar {
            if let session = viewModel.session(in: store) {
                Button {
                    viewModel.showingEditSession = true
                } label: {
                    Label("Edit Session", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.delete(session, from: store)
                    dismiss()
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditSession) {
            if let session = viewModel.session(in: store) {
                NavigationStack {
                    SessionFormView(session: session)
                }
            }
        }
    }
}
