import SwiftUI

/// The "Season Development" section on the player detail screen: attendance,
/// scoring, effort, and a recent-form sparkline drawn from the team's games.
struct PlayerDevelopmentSection: View {
    let profile: PlayerDevelopment

    var body: some View {
        Section {
            if profile.timeline.isEmpty {
                Text("No game data yet. Record attendance and post-game reports to build \(Text("this player's").fontWeight(.semibold)) season profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Attendance") {
                    Text(attendanceText)
                        .foregroundStyle(attendanceColor)
                        .fontWeight(.semibold)
                }
                if profile.minutes > 0 {
                    LabeledContent("Minutes Played", value: "\(profile.minutes)'")
                }
                LabeledContent("Goals · Assists", value: "\(profile.goals)G · \(profile.assists)A")
                if profile.averageEffort > 0 {
                    LabeledContent("Average Effort") {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "star.fill")
                            Text(String(format: "%.1f / 5", profile.averageEffort))
                        }
                        .foregroundStyle(Color.caution)
                    }
                }

                let form = profile.recentForm()
                if !form.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Recent Form")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        EffortSparkline(games: form)
                    }
                    .padding(.vertical, Spacing.xxs)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(formAccessibilityLabel(form))
                }
            }
        } header: {
            Text("Season Development")
        } footer: {
            if !profile.timeline.isEmpty {
                Text("Attendance counts games marked present or late; goals, assists, and effort come from post-game reports.")
            }
        }
    }

    private var attendanceText: String {
        guard let rate = profile.attendanceRate else { return "—" }
        return "\(Int((rate * 100).rounded()))% (\(profile.gamesAttended)/\(profile.gamesTracked))"
    }

    private var attendanceColor: Color {
        guard let rate = profile.attendanceRate else { return .secondary }
        if rate >= 0.85 { return .positive }
        if rate >= 0.6 { return .caution }
        return .critical
    }

    private func formAccessibilityLabel(_ games: [PlayerGameLine]) -> String {
        let results = games.compactMap { line -> String? in
            guard let outcome = line.outcome else { return nil }
            switch outcome {
            case .win: return "win"
            case .loss: return "loss"
            case .draw: return "draw"
            }
        }
        var parts = ["Recent form"]
        if !results.isEmpty { parts.append("last \(results.count) games: " + results.joined(separator: ", ")) }
        let contributions = games.reduce(0) { $0 + $1.contributions }
        if contributions > 0 { parts.append("\(contributions) goal contribution\(contributions == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

/// A compact per-game bar chart of recent effort, tinted by the team result,
/// with a goal-contribution dot above games where the player scored or assisted.
private struct EffortSparkline: View {
    let games: [PlayerGameLine]

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            ForEach(games) { game in
                VStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(game.contributions > 0 ? Color.brand : .clear)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: game.outcome))
                        .frame(width: 14, height: height(for: game.effort))
                    Text(game.outcome?.rawValue ?? "·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color(for: game.outcome))
                }
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    /// Effort 0 (unrated) gets a short neutral stub; 1...5 scales to full height.
    private func height(for effort: Int) -> CGFloat {
        guard effort > 0 else { return 4 }
        return 8 + CGFloat(effort) / 5 * 22
    }

    private func color(for outcome: GameOutcome?) -> Color {
        switch outcome {
        case .win: return .positive
        case .loss: return .critical
        case .draw: return .caution
        case nil: return Color.secondary.opacity(0.4)
        }
    }
}
