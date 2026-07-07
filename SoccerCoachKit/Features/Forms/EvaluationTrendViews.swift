import SwiftUI

/// The player-detail "Evaluation Trends" section: average readiness plus a
/// readiness-over-time and effort-over-time sparkline, all aggregated through
/// the engine from every source (game-day check-ins and engine evaluations).
/// Complements `PlayerReadinessSection` (which explains *why* — the biggest
/// difference between strong and weak games) with *when*.
struct EvaluationTrendSection: View {
    let readiness: [TrendPoint]
    let averageReadiness: Double?
    let effort: [TrendPoint]

    var body: some View {
        if !readiness.isEmpty || !effort.isEmpty {
            Section {
                if let average = averageReadiness {
                    LabeledContent("Average Readiness") {
                        Text(String(format: "%.1f / 5", average))
                            .fontWeight(.semibold)
                            .foregroundStyle(readinessColor(average))
                    }
                }

                if !readiness.isEmpty {
                    trendBlock(title: "Readiness over time", points: readiness, tint: .brand, unit: "readiness")
                }

                if !effort.isEmpty {
                    trendBlock(title: "Effort over time", points: effort, tint: .caution, unit: "effort")
                }
            } header: {
                Text("Evaluation Trends")
            } footer: {
                Text("Readiness is the mean of each pre-match check-in's wellness scales. Both trends aggregate everything recorded — game-day check-ins and engine evaluations alike — oldest to newest.")
            }
        }
    }

    private func trendBlock(title: String, points: [TrendPoint], tint: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TrendSparkline(points: points, tint: tint, unit: unit)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func readinessColor(_ value: Double) -> Color {
        if value >= 4 { return .positive }
        if value >= 3 { return .caution }
        return .critical
    }
}

/// A compact 1–5 bar sparkline for a readiness/effort series.
struct TrendSparkline: View {
    let points: [TrendPoint]
    let tint: Color
    /// Word used in the VoiceOver summary ("readiness"/"effort").
    var unit: String = "value"
    private let scaleMax: Double = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.85))
                    .frame(width: 12, height: height(point.value))
            }
        }
        .frame(height: 46, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func height(_ value: Double) -> CGFloat {
        6 + CGFloat(min(value, scaleMax) / scaleMax) * 34
    }

    private var accessibilityLabel: String {
        guard let last = points.last?.value else { return "No \(unit) recorded" }
        let series = points.map { String(format: "%.1f", $0.value) }.joined(separator: ", ")
        return "\(unit.capitalized) trend over \(points.count) entr\(points.count == 1 ? "y" : "ies"), latest \(String(format: "%.1f", last)): \(series)"
    }
}

/// One row of the team dashboard's squad-readiness board.
struct SquadReadinessRow: View {
    let entry: SquadReadinessEntry

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.player.name)
                    .font(.subheadline.weight(.semibold))
                Text("#\(entry.player.number) · \(entry.player.position.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let average = entry.averageReadiness {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(String(format: "%.1f", average))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(color(average))
                        .monospacedDigit()
                    Text("\(entry.sampleCount) check-in\(entry.sampleCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func color(_ value: Double) -> Color {
        if value >= 4 { return .positive }
        if value >= 3 { return .caution }
        return .critical
    }

    private var accessibilityLabel: String {
        guard let average = entry.averageReadiness else {
            return "\(entry.player.name), no check-ins recorded"
        }
        return "\(entry.player.name), average readiness \(String(format: "%.1f", average)) of 5, from \(entry.sampleCount) check-in\(entry.sampleCount == 1 ? "" : "s")"
    }
}
