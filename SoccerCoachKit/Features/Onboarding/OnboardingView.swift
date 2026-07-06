import SwiftUI

/// First-run experience: welcomes the coach and creates their first team, or
/// lets them explore the built-in sample data. Presented as a full-screen cover
/// until `hasOnboarded` is set.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    let finish: () -> Void

    @State private var teamName = ""
    @State private var ageGroup: AgeGroup = .u10
    @State private var season = OnboardingView.currentSeason
    @State private var accent: TeamAccent = .teal

    private static var currentSeason: String {
        "\(Calendar.current.component(.year, from: Date()))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                hero
                setupCard
                actions
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: "soccerball.inverse")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Welcome, Coach")
                .font(AppFont.display)
            Text("Manage your roster, run game day, plan training, and track the season — all in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                featureRow("person.3.fill", "Roster, attendance & RSVPs")
                featureRow("sportscourt.fill", "Live game day: clock, subs & score")
                featureRow("calendar", "Schedule with a unified calendar")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Create your team").sectionHeaderStyle()

            TextField("Team name", text: $teamName)
                .textFieldStyle(.roundedBorder)
                .font(.body)

            Picker("Age group", selection: $ageGroup) {
                ForEach(AgeGroup.allCases) { group in
                    Text(group.rawValue).tag(group)
                }
            }

            HStack {
                Text("Season")
                Spacer()
                TextField("Season", text: $season)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Accent")
                    .font(.subheadline)
                accentPicker
            }
        }
        .cardStyle()
    }

    private var accentPicker: some View {
        HStack(spacing: Spacing.md) {
            ForEach(TeamAccent.allCases) { option in
                Circle()
                    .fill(option.color)
                    .frame(width: 30, height: 30)
                    .overlay {
                        if option == accent {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: option == accent ? 0 : 1))
                    .onTapGesture { accent = option }
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(option == accent ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            Button {
                store.startFresh(name: teamName, ageGroup: ageGroup, season: season, accent: accent)
                finish()
            } label: {
                Text("Create My Team")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Explore with sample data") { finish() }
                .font(.subheadline)
        }
        .padding(.top, Spacing.xs)
    }
}
