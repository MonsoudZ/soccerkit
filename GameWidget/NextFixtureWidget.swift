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
        let fixture = WidgetSharedStore.load()
        let entry = FixtureEntry(date: Date(), fixture: fixture)
        // Refresh soon after kickoff (or in an hour if there's nothing scheduled).
        let nextRefresh = fixture.map { $0.date.addingTimeInterval(2 * 3600) }
            ?? Date().addingTimeInterval(3600)
        let policy: TimelineReloadPolicy = .after(max(nextRefresh, Date().addingTimeInterval(900)))
        completion(Timeline(entries: [entry], policy: policy))
    }
}

struct NextFixtureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFixture", provider: FixtureProvider()) { entry in
            FixtureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Fixture")
        .description("Your team's next game at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
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
