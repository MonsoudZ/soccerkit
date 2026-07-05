import SwiftUI

/// Central layout tokens. Views reference these instead of hard-coding numbers,
/// so spacing, radius, and elevation stay consistent and tunable in one place.
/// Color lives in `Palette.swift`; type styles in `Typography.swift`.

/// Spacing scale (points) — a 4pt-based rhythm.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 28
}

/// Corner radii (points).
enum CornerRadius {
    static let small: CGFloat = 10
    static let card: CGFloat = 16
    static let large: CGFloat = 22
    static let pill: CGFloat = 999
}

/// Card elevation. Subtle in light mode; in dark mode the lighter card surface
/// already reads as lift, so the shadow stays gentle.
enum Elevation {
    static let cardColor = Color.black.opacity(0.08)
    static let cardRadius: CGFloat = 10
    static let cardYOffset: CGFloat = 5
}
