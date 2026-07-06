import SwiftUI

extension View {
    /// The standard card container: pad, fill with the themed card surface,
    /// round the corners, and lift with a subtle shadow.
    func cardStyle(padding: CGFloat = Spacing.xl) -> some View {
        self
            .padding(padding)
            .surfaceStyle()
    }

    /// Fills a view with the themed card surface, rounds it, and applies
    /// elevation — without adding padding (for views that manage their insets).
    func surfaceStyle() -> some View {
        modifier(SurfaceStyle())
    }

    /// Rounds a view to the standard card corner radius.
    func cardCorners() -> some View {
        clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    }

    /// Fills a (ScrollView-based) screen with the themed screen surface.
    func screenBackground() -> some View {
        modifier(ScreenBackgroundStyle())
    }

    /// Themes a `List`/`Form` screen: replaces the system grouped background and
    /// row surfaces with the active theme's screen and card colors.
    func themedList() -> some View {
        modifier(ThemedListStyle())
    }
}

private struct SurfaceStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.card)
            .cardCorners()
            // A hairline edge gives cards a crisp, defined border — subtle depth
            // that reads especially well against dark screen surfaces.
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
            )
            .shadow(
                color: Elevation.cardColor,
                radius: Elevation.cardRadius,
                x: 0,
                y: Elevation.cardYOffset
            )
    }
}

private struct ScreenBackgroundStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.screen.ignoresSafeArea())
    }
}

private struct ThemedListStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.screen.ignoresSafeArea())
            .listRowBackground(theme.card)
    }
}
