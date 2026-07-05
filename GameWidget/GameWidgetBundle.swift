import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GameWidgetBundle: WidgetBundle {
    var body: some Widget {
        GameLiveActivity()
        NextFixtureWidget()
    }
}

// MARK: - Helpers

// `Color(hex:)` is defined in the shared NextFixtureView.swift.

private func clockString(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// MARK: - Live Activity

struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = Color(hex: context.attributes.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ScorePill(
                        name: context.attributes.teamName,
                        score: context.state.teamScore,
                        tint: accent,
                        alignment: .leading
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ScorePill(
                        name: context.attributes.opponentName,
                        score: context.state.opponentScore,
                        tint: .secondary,
                        alignment: .trailing
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        clockView(for: context, font: .title3.monospacedDigit().weight(.semibold))
                        Text(context.state.periodLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(
                        context.state.isRunning ? "Live" : "Paused",
                        systemImage: context.state.isRunning ? "dot.radiowaves.left.and.right" : "pause.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.isRunning ? accent : .secondary)
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Text("\(context.state.teamScore)–\(context.state.opponentScore)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
            } compactTrailing: {
                clockView(for: context, font: .caption.monospacedDigit())
            } minimal: {
                Image(systemName: "soccerball")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }

    /// The clock: a self-advancing timer while running, a frozen value while paused.
    @ViewBuilder
    private func clockView(for context: ActivityViewContext<GameActivityAttributes>, font: Font) -> some View {
        if context.state.isRunning {
            Text(context.state.clockStart, style: .timer)
                .font(font)
                .monospacedDigit()
        } else {
            Text(clockString(context.state.frozenElapsed))
                .font(font)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<GameActivityAttributes>

    private var accent: Color { Color(hex: context.attributes.accentHex) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(context.state.isRunning ? "Live" : "Paused",
                      systemImage: context.state.isRunning ? "dot.radiowaves.left.and.right" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.isRunning ? accent : .secondary)
                Spacer()
                Text(context.state.periodLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                teamColumn(context.attributes.teamName, context.state.teamScore, tint: accent)
                VStack(spacing: 2) {
                    clock
                    Text("–").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                teamColumn(context.attributes.opponentName, context.state.opponentScore, tint: .primary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var clock: some View {
        if context.state.isRunning {
            Text(context.state.clockStart, style: .timer)
                .font(.title2.monospacedDigit().weight(.bold))
                .multilineTextAlignment(.center)
        } else {
            Text(clockString(context.state.frozenElapsed))
                .font(.title2.monospacedDigit().weight(.bold))
        }
    }

    private func teamColumn(_ name: String, _ score: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text("\(score)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Small components

private struct ScorePill: View {
    let name: String
    let score: Int
    let tint: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text("\(score)")
                .font(.title.weight(.heavy).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
