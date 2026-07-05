import SwiftUI

extension Color {
    /// 24-bit RGB hex string ("4F46E5") → Color, falling back to accentColor.
    init(hex: String) {
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value), hex.count >= 6 else {
            self = .accentColor
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The Home Screen widget's content. Lives in the shared set (app + widget) so
/// it can be previewed/rendered from either side. `compact` drives the small
/// family's tighter layout.
struct NextFixtureView: View {
    let fixture: FixtureSnapshot?
    var compact: Bool = false

    var body: some View {
        if let fixture {
            content(fixture)
        } else {
            emptyState
        }
    }

    private func content(_ fixture: FixtureSnapshot) -> some View {
        let accent = Color(hex: fixture.accentHex)
        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "soccerball")
                    .font(.caption2)
                    .foregroundStyle(accent)
                Text("NEXT GAME")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(fixture.isHome ? "HOME" : "AWAY")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.16))
                    .foregroundStyle(accent)
                    .clipShape(Capsule())
            }

            Text(fixture.teamName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("vs \(fixture.opponent)")
                .font(compact ? .headline : .title3.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            Spacer(minLength: 0)

            // Relative countdown that keeps itself current on the timeline.
            Text(fixture.date, format: .relative(presentation: .named))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)

            Text(fixture.date, format: .dateTime.weekday().month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !compact, !fixture.location.isEmpty {
                Label(fixture.location, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No upcoming games")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Lock Screen (`.accessoryRectangular`) layout. Accessory widgets render in
/// a monochrome/vibrant mode, so this leans on SF Symbols, weight, and the text
/// hierarchy rather than color; `.widgetAccentable()` lets the whole thing pick
/// up an accent-tinted Lock Screen.
struct AccessoryFixtureView: View {
    let fixture: FixtureSnapshot?

    var body: some View {
        if let fixture {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "soccerball")
                    Text(fixture.isHome ? "NEXT · HOME" : "NEXT · AWAY")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.caption2)
                .widgetAccentable()

                Text("vs \(fixture.opponent)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(fixture.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Label("No upcoming games", systemImage: "soccerball")
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
