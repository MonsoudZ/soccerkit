import SwiftUI

struct TrainingPlannerView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = TrainingPlannerViewModel()

    var body: some View {
        List {
            ForEach(store.teamSessions) { session in
                NavigationLink {
                    SessionDetailView(sessionID: session.id)
                } label: {
                    SessionSummaryCard(session: session)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.delete(session, from: store)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .themedList()
        .toolbar {
            Button {
                viewModel.showingNewSession = true
            } label: {
                Label("New Session", systemImage: "plus")
            }
        }
        .sheet(isPresented: $viewModel.showingNewSession) {
            NavigationStack {
                SessionFormView()
            }
        }
    }
}
