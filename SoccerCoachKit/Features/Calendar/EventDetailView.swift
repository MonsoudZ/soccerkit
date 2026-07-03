import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EventDetailViewModel

    init(eventID: UUID) {
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(eventID: eventID))
    }

    var body: some View {
        Group {
            if let event = viewModel.event(in: store) {
                List {
                    Section("Event") {
                        LabeledContent("Title", value: event.title)
                        LabeledContent("Type", value: event.kind.rawValue)
                        LabeledContent("Team", value: store.teamName(for: event.teamID))
                        if event.isMultiDay, let endDate = event.endDate {
                            LabeledContent("Starts", value: event.date.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Ends", value: endDate.formatted(date: .abbreviated, time: .omitted))
                        } else {
                            LabeledContent("Date", value: event.date.formatted(date: .abbreviated, time: .omitted))
                            LabeledContent("Time", value: event.date.formatted(date: .omitted, time: .shortened))
                        }
                        if !event.location.isEmpty {
                            LabeledContent("Location", value: event.location)
                        }
                    }

                    if !event.notes.isEmpty {
                        Section("Notes") {
                            Text(event.notes)
                        }
                    }

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: event.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: event)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(event.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }
                }
            } else {
                EmptyStateView(title: "Event Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(viewModel.event(in: store)?.title ?? "Event")
        .toolbar {
            if let event = viewModel.event(in: store) {
                Button {
                    viewModel.showingEditEvent = true
                } label: {
                    Label("Edit Event", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.delete(event, from: store)
                    dismiss()
                } label: {
                    Label("Delete Event", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditEvent) {
            if let event = viewModel.event(in: store) {
                NavigationStack {
                    EventFormView(event: event)
                }
            }
        }
    }
}
