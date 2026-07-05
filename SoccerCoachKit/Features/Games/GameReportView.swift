import SwiftUI

struct GameReportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameReportViewModel

    init(game: GameEvent) {
        _viewModel = StateObject(wrappedValue: GameReportViewModel(game: game))
    }

    var body: some View {
        Form {
            Section("Result") {
                Toggle("Record final score", isOn: $viewModel.recordScore)
                if viewModel.recordScore {
                    Stepper("Our Score: \(viewModel.teamScore)", value: $viewModel.teamScore, in: 0...50)
                    Stepper("Opponent: \(viewModel.opponentScore)", value: $viewModel.opponentScore, in: 0...50)
                }
            }

            Section {
                if store.roster.isEmpty {
                    Text("Add players to the roster to record reports.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.roster) { player in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("#\(player.number)  \(player.name)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }

                            Stepper("Goals: \(viewModel.binding(\.goals, for: player.id).wrappedValue)", value: viewModel.binding(\.goals, for: player.id), in: 0...20)
                            Stepper("Assists: \(viewModel.binding(\.assists, for: player.id).wrappedValue)", value: viewModel.binding(\.assists, for: player.id), in: 0...20)

                            HStack {
                                Text("Effort")
                                    .font(.subheadline)
                                Spacer()
                                EffortStars(rating: viewModel.binding(\.effort, for: player.id))
                            }

                            TextField("Development focus", text: viewModel.binding(\.developmentFocus, for: player.id), axis: .vertical)
                                .lineLimit(1...3)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Player Reports")
            } footer: {
                Text("Goals, assists, an effort rating, and a development focus for each player.")
            }
        }
        .themedList()
        .navigationTitle("Post-Game Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(into: store)
                    dismiss()
                }
            }
        }
    }
}

/// A 1...5 star rating; tapping the current rating clears it back to unrated.
struct EffortStars: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        rating = (rating == value) ? 0 : value
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Unrated" : "\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            // Lets VoiceOver users swipe up/down to change the rating.
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}
