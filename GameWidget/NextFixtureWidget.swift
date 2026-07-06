import SwiftUI
import WidgetKit

struct FixtureEntry: TimelineEntry {
    let date: Date
    let fixture: FixtureSnapshot?
}

/// Reads the shared next fixture and refreshes once the game has kicked off (by
/// which point the app will have republished the following one).
struct FixtureProvider: TimelineProvider {
    func placeholder(in context: Context) -> FixtureEntry {
        FixtureEntry(date: Date(), fixture: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FixtureEntry) -> Void) {
        let fixture = context.isPreview ? .sample : WidgetSharedStore.load()
        completion(FixtureEntry(date: Date(), fixture: fixture))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FixtureEntry>) -> Void) {
        let now = Date()
        // Ignore a fixture that has already kicked off (the app may not have
        // republished the next one yet).
        let fixture = WidgetSharedStore.load().flatMap { $0.date > now ? $0 : nil }

        guard let fixture else {
            completion(Timeline(entries: [FixtureEntry(date: now, fixture: nil)],
                                policy: .after(now.addingTimeInterval(3600))))
            return
        }

        // One entry now plus one per following midnight up to kickoff, so the
        // relative countdown / "days until" stays current instead of freezing.
        let calendar = Calendar.current
        var entries = [FixtureEntry(date: now, fixture: fixture)]
        var day = now
        for _ in 0..<14 {
            guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)),
                  midnight < fixture.date else { break }
            entries.append(FixtureEntry(date: midnight, fixture: fixture))
            day = midnight
        }
        completion(Timeline(entries: entries, policy: .after(fixture.date)))
    }
}

struct NextFixtureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFixture", provider: FixtureProvider()) { entry in
            FixtureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Fixture")
        .description("Your team's next game at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

/// Picks the right layout and container treatment for the current widget family,
/// including the Lock Screen accessory families.
private struct FixtureWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FixtureEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryFixtureView(fixture: entry.fixture)
                .accessoryContainer()
        case .accessoryInline:
            // A single tinted line beside the Lock Screen clock.
            Label(inlineText, systemImage: "soccerball")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                AccessoryCircularFixtureView(fixture: entry.fixture, now: entry.date)
            }
            .accessoryContainer()
        default:
            NextFixtureView(fixture: entry.fixture, compact: family == .systemSmall)
                .widgetContainer()
        }
    }

    private var inlineText: String {
        guard let fixture = entry.fixture else { return "No games" }
        return "vs \(fixture.opponent)"
    }
}

private extension View {
    /// Content margins/background for the Home Screen (system) families.
    @ViewBuilder
    func widgetContainer() -> some View {
        if #available(iOS 17.0, *) {
            self.padding(4).containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.padding()
        }
    }

    /// Lock Screen accessory widgets sit on the wallpaper, so their container is
    /// clear.
    @ViewBuilder
    func accessoryContainer() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.clear, for: .widget)
        } else {
            self
        }
    }
}
