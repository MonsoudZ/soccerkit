import SwiftUI

/// The Roster screen's team settings, as a card that collapses.
///
/// This block used to sit open above the roster on a screen whose job is the
/// roster, pushing the players below the fold. Collapsed it keeps a summary in
/// the header — age group, format, and how full the squad is — so the facts a
/// coach glances for are still there without opening anything, and the
/// expand/collapse choice is remembered.
///
/// Below the settings a coach can change sits the age group's US Soccer
/// standard, read-only: the rulebook for the group they've selected.
struct TeamSettingsCard: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("rosterTeamSettingsExpanded") private var isExpanded = false

    private var team: Team { store.selectedTeam }
    private var standard: USSoccerStandard { team.ageGroup.standard }
    private var isOverRosterLimit: Bool { store.roster.count > standard.maxRosterSize }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                Picker("Age Group", selection: ageGroupBinding) {
                    ForEach(AgeGroup.allCases) { ageGroup in
                        Text(ageGroup.rawValue).tag(ageGroup)
                    }
                }

                Picker("Match Periods", selection: periodFormatBinding) {
                    ForEach(PeriodFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Stepper(
                    "Min. Minutes / Player: \(team.defaultMinimumMinutes)",
                    value: minimumMinutesBinding,
                    in: 0...standard.gameMinutes
                )

                standardRows
            } label: {
                summary
            }
        } footer: {
            footer
        }
    }

    // MARK: - Collapsed summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Team Settings")
            Text("\(team.ageGroup.rawValue) · \(standard.formatLabel) · \(store.roster.count)/\(standard.maxRosterSize)")
                .font(.caption)
                .foregroundStyle(isOverRosterLimit ? .orange : .secondary)
        }
        // One label, so VoiceOver reads the summary rather than two fragments.
        .accessibilityElement(children: .combine)
    }

    // MARK: - The standard

    @ViewBuilder
    private var standardRows: some View {
        Text("US Soccer Standard")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)

        LabeledContent("Format", value: standard.formatLabel)
        LabeledContent("Roster Limit") {
            Text("\(store.roster.count) / \(standard.maxRosterSize)")
                .foregroundStyle(isOverRosterLimit ? .orange : .secondary)
        }
        LabeledContent("Game Length", value: standard.gameLengthLabel)
        LabeledContent("Ball Size", value: "\(standard.ballSize)")
        LabeledContent("Field", value: standard.fieldLabel)
        LabeledContent("Goal", value: standard.goalLabel)
        LabeledContent("Build-Out Line", value: standard.hasBuildOutLine ? "Yes" : "No")
        LabeledContent("Heading", value: standard.heading.rawValue)
        LabeledContent("Offside", value: standard.offsideEnforced ? "Yes" : "No")
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        // Only built when there's something to say: an always-present empty
        // stack still reserves footer height, which left a gap between the
        // closed card and the roster.
        if isOverRosterLimit || isExpanded {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Stays visible when the card is closed: being over the limit
                // is something to act on, not to go looking for.
                if isOverRosterLimit {
                    Label(
                        "\(store.roster.count) players — \(standard.maxRosterSize) is the usual max for \(standard.formatLabel).",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                if isExpanded {
                    Text("Format, ball, field, goal, build-out line, heading and offside are the US Soccer standard. Period length and roster limit vary by league — these are the common values.")
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Bindings

    private var ageGroupBinding: Binding<AgeGroup> {
        Binding { team.ageGroup } set: { store.setAgeGroup($0, for: team) }
    }

    private var periodFormatBinding: Binding<PeriodFormat> {
        Binding { team.periodFormat } set: { store.setPeriodFormat($0, for: team) }
    }

    private var minimumMinutesBinding: Binding<Int> {
        Binding { team.defaultMinimumMinutes } set: { store.setDefaultMinimumMinutes($0, for: team) }
    }
}
