import SwiftUI

/// The "Match Readiness" section on the player detail: average pre-match
/// readiness and — the whole point — the single factor that most separates this
/// player's strong games from their weak ones, so a coach can act on it.
struct PlayerReadinessSection: View {
    let insight: PlayerMatchInsight

    var body: some View {
        if insight.gamesWithCheckIn > 0 {
            Section {
                if let readiness = insight.averageReadiness {
                    LabeledContent("Average Readiness") {
                        HStack(spacing: Spacing.md) {
                            Text(String(format: "%.1f / 5", readiness))
                                .fontWeight(.semibold)
                                .foregroundStyle(color(for: readiness))
                        }
                    }
                }

                if let top = insight.topDifferentiator, insight.hasComparison {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Biggest difference: \(top.label)")
                            .font(.subheadline.weight(.semibold))
                        Text(insightSentence(top))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        comparisonBars(top)
                    }
                    .padding(.vertical, Spacing.xxs)

                    ForEach(insight.differentiators.dropFirst().prefix(3)) { factor in
                        LabeledContent(factor.label) {
                            Text("\(fmt(factor.strongAverage)) vs \(fmt(factor.weakAverage))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("Recorded for \(insight.gamesWithCheckIn) game\(insight.gamesWithCheckIn == 1 ? "" : "s"). Once there are both strong (4–5) and weak (1–2) games rated, the biggest difference-maker will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Match Readiness")
            } footer: {
                if insight.hasComparison {
                    Text("Compares pre-match check-ins on this player's strong games (rated 4–5) vs weak games (1–2). Green = higher before strong games.")
                }
            }
        }
    }

    private func insightSentence(_ factor: FactorComparison) -> String {
        String(
            format: "%@ averages %@ before strong games vs %@ before weak ones — a %@-point gap.",
            factor.label, fmt(factor.strongAverage), fmt(factor.weakAverage), fmt(factor.gap)
        )
    }

    private func comparisonBars(_ factor: FactorComparison) -> some View {
        VStack(spacing: Spacing.xs) {
            bar(title: "Strong games", value: factor.strongAverage, tint: .positive)
            bar(title: "Weak games", value: factor.weakAverage, tint: .critical)
        }
    }

    private func bar(title: String, value: Double, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tint).frame(width: geo.size.width * CGFloat(value / 5))
                }
            }
            .frame(height: 8)
            Text(fmt(value))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func color(for readiness: Double) -> Color {
        if readiness >= 4 { return .positive }
        if readiness >= 3 { return .caution }
        return .critical
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
}
