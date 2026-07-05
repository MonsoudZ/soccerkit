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
            NextFixtureView(fixture: entry.fixture, compact: false)
                .widgetContainer()
        }
        .configurationDisplayName("Next Fixture")
        .description("Your team's next game at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension View {
    /// Applies the widget's content margins/background across OS versions.
    @ViewBuilder
    func widgetContainer() -> some View {
        if #available(iOS 17.0, *) {
            self.padding(4).containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.padding()
        }
    }
}
