import SwiftUI

/// Pre- and post-match questionnaires for a game: a coach plan/review plus
/// per-player readiness check-ins and reflections. The coach records answers
/// on each player's behalf, the same way attendance and reports work.
struct MatchQuestionnaireView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MatchQuestionnaireViewModel
    @State private var phase: Phase

    enum Phase: String, CaseIterable, Identifiable {
        case pre = "Pre-Match", post = "Post-Match"
        var id: String { rawValue }
    }

    init(game: GameEvent, phase: Phase = .pre) {
        _viewModel = StateObject(wrappedValue: MatchQuestionnaireViewModel(game: game))
        _phase = State(initialValue: phase)
    }

    var body: some View {
        Form {
            Section {
                Picker("Questionnaire", selection: $phase) {
                    ForEach(Phase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if phase == .pre {
                coachPreSection
                playerPreSection
            } else {
                coachPostSection
                playerPostSection
            }
        }
        .themedList()
        .navigationTitle("Match Check-In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(into: store)
                    dismiss()
                }
            }
        }
    }

    // MARK: Pre-match

    private var coachPreSection: some View {
        Section {
            LabeledTextField("Objective", text: $viewModel.coachPre.objective, prompt: "e.g. Keep our shape when we lose the ball")
            LabeledTextField("Key matchup", text: $viewModel.coachPre.keyMatchup, prompt: "e.g. Their #10 in midfield")
            LabeledTextField("Focus points", text: $viewModel.coachPre.focusPoints, prompt: "1–3 things to get right")
            LabeledTextField("Watch for", text: $viewModel.coachPre.watchFor, prompt: "Their threat / our risk")
        } header: {
            Label("Coach — Game Plan", systemImage: "list.clipboard")
        }
    }

    private var playerPreSection: some View {
        Section {
            if store.roster.isEmpty {
                Text("Add players to the roster to record check-ins.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.roster) { player in
                    DisclosureGroup {
                        ScaleRow(label: "Sleep", value: viewModel.preBinding(\.sleep, for: player.id))
                        ScaleRow(label: "Energy", value: viewModel.preBinding(\.energy, for: player.id))
                        ScaleRow(label: "Freshness (soreness)", value: viewModel.preBinding(\.freshness, for: player.id))
                        ScaleRow(label: "Hydration", value: viewModel.preBinding(\.hydration, for: player.id))
                        ScaleRow(label: "Nutrition", value: viewModel.preBinding(\.nutrition, for: player.id))
                        ScaleRow(label: "Mood", value: viewModel.preBinding(\.mood, for: player.id))
                        ScaleRow(label: "Composure (nerves)", value: viewModel.preBinding(\.composure, for: player.id))
                        ScaleRow(label: "Focus", value: viewModel.preBinding(\.focus, for: player.id))
                        YesNoRow(label: "Warmed up properly?", value: viewModel.preBinding(\.warmedUp, for: player.id))
                        YesNoRow(label: "Any pain or niggle?", value: viewModel.preBinding(\.hasPain, for: player.id))
                        LabeledTextField("Note", text: viewModel.preBinding(\.note, for: player.id), prompt: "Anything to flag")
                    } label: {
                        PlayerRowHeader(player: player, detail: viewModel.preProgress(for: player.id))
                    }
                }
            }
        } header: {
            Label("Player Readiness", systemImage: "figure.strengthtraining.functional")
        } footer: {
            Text("Rate 1–5 (higher is better). Higher readiness before games should track with better performances — the player profile flags the biggest difference.")
        }
    }

    // MARK: Post-match

    private var coachPostSection: some View {
        Section {
            ScaleRow(label: "Team performance", value: $viewModel.coachPost.teamPerformance)
            LabeledTextField("What worked", text: $viewModel.coachPost.whatWorked, prompt: "Keep doing this")
            LabeledTextField("What to adjust", text: $viewModel.coachPost.whatToAdjust, prompt: "Fix for next time")
            LabeledTextField("Standout player", text: $viewModel.coachPost.standoutPlayer, prompt: "Who led the way")
        } header: {
            Label("Coach — Review", systemImage: "text.magnifyingglass")
        }
    }

    private var playerPostSection: some View {
        Section {
            if store.roster.isEmpty {
                Text("Add players to the roster to record reflections.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.roster) { player in
                    DisclosureGroup {
                        ScaleRow(label: "Effort (RPE)", value: viewModel.postBinding(\.exertion, for: player.id))
                        ScaleRow(label: "Performance", value: viewModel.postBinding(\.performance, for: player.id))
                        ScaleRow(label: "Enjoyment", value: viewModel.postBinding(\.enjoyment, for: player.id))
                        ScaleRow(label: "Fatigue", value: viewModel.postBinding(\.fatigue, for: player.id))
                        ScaleRow(label: "Confidence", value: viewModel.postBinding(\.confidence, for: player.id))
                        YesNoRow(label: "Injury during game?", value: viewModel.postBinding(\.hadInjury, for: player.id))
                        LabeledTextField("What went well", text: viewModel.postBinding(\.wentWell, for: player.id), prompt: "A positive to build on")
                        LabeledTextField("What to work on", text: viewModel.postBinding(\.workOn, for: player.id), prompt: "One focus for training")
                    } label: {
                        PlayerRowHeader(player: player, detail: viewModel.postProgress(for: player.id))
                    }
                }
            }
        } header: {
            Label("Player Reflection", systemImage: "bubble.left.and.text.bubble.right")
        } footer: {
            Text("The performance rating (or the post-game report effort) is what the profile uses to compare good vs poor games.")
        }
    }
}

/// A compact disclosure header: jersey badge, name, and a progress detail line.
private struct PlayerRowHeader: View {
    let player: Player
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            PlayerAvatar(number: player.number, position: player.position)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A titled, multi-line text field used across the questionnaire forms.
private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    init(_ title: String, text: Binding<String>, prompt: String = "") {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt.isEmpty ? title : prompt, text: $text, axis: .vertical)
                .lineLimit(1...4)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
