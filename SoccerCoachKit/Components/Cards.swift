import SwiftUI

struct TeamHeader: View {
    @Environment(\.theme) private var theme
    let team: Team

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team.name)
                .font(AppFont.display)
            HStack(spacing: 8) {
                Label(team.ageGroup.rawValue, systemImage: "shield")
                Label(team.season, systemImage: "leaf")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xxl)
        .background(
            LinearGradient(
                colors: [team.accentColor.opacity(0.30), team.accentColor.opacity(0.12), theme.card],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cardCorners()
        .shadow(color: Elevation.cardColor, radius: Elevation.cardRadius, x: 0, y: Elevation.cardYOffset)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value)
                .font(AppFont.metric)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .surfaceStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(title)")
    }
}

struct GameSummaryCard: View {
    @EnvironmentObject private var store: AppStore
    let game: GameEvent

    var body: some View {
        let summary = store.rsvpSummary(game.rsvps)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs \(game.opponent)")
                        .font(.headline)
                    Text(game.date, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(game.isHome ? "Home" : "Away")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }

            if !game.location.isEmpty {
                Label(game.location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(summary.going) going", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.positive)
                Label("\(summary.maybe) maybe", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(Color.caution)
                Label("\(summary.notGoing) out", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Color.critical)
            }
            .font(.caption)
        }
        .padding()
        .surfaceStyle()
    }
}

struct SessionSummaryCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TrainingSession

    var body: some View {
        let summary = store.attendanceSummary(for: session)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text(session.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(totalMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.objective)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(summary.present), total: Double(max(summary.total, 1)))

            Text("\(summary.present) of \(summary.total) expected players marked present or late")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .surfaceStyle()
    }

    var totalMinutes: Int {
        session.blocks.reduce(0) { $0 + $1.minutes }
    }
}

struct DrillCard: View {
    @EnvironmentObject private var store: AppStore
    let drill: Drill

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(drill.title)
                    .font(.headline)
                Spacer()
                Label("\(drill.durationMinutes) min", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(drill.category.rawValue)
                Text(store.teamName(for: drill.teamID))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            TagChipsView(tags: drill.tags)

            HStack(spacing: 10) {
                if !drill.fieldSize.isEmpty {
                    Label(drill.fieldSize, systemImage: "rectangle.dashed")
                }
                if !drill.equipment.isEmpty {
                    Label("\(drill.equipment.count) equipment", systemImage: "cone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(drill.fieldSetup)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(drill.coachingPoints.enumerated()), id: \.offset) { _, point in
                    Label(point, systemImage: "checkmark.circle")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
