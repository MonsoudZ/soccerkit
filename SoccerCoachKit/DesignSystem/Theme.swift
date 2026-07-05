import SwiftUI

/// A complete visual theme: an accent plus a bespoke, light/dark-adaptive
/// surface palette. Themes are injected via `@Environment(\.theme)` and switched
/// at runtime by `ThemeManager`. Semantic status colors (`positive`/`caution`/…)
/// live in `Palette.swift` and are intentionally theme-independent — a warning is
/// a warning in every theme.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    /// Accent / brand tint. Also applied app-wide via `.tint(...)`.
    let brand: Color
    /// The screen (behind-content) surface.
    let screen: Color
    /// The card / list-row surface.
    let card: Color
    /// A slightly raised surface (menus, nested cards).
    let cardElevated: Color
    /// Hairline separators / strokes.
    let hairline: Color

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }
}

extension Theme {
    /// Indigo on cool neutrals — the default.
    static let indigo = Theme(
        id: "indigo",
        name: "Indigo",
        brand: Color(light: 0x4F46E5, dark: 0x8B8CF7),
        screen: Color(light: 0xF2F3F7, dark: 0x0B0C11),
        card: Color(light: 0xFFFFFF, dark: 0x1A1B22),
        cardElevated: Color(light: 0xFFFFFF, dark: 0x24252E),
        hairline: Color(light: 0xE4E6EB, dark: 0x2C2E37)
    )

    /// Grass green on faintly green-tinted surfaces — a soccer-native look.
    static let pitch = Theme(
        id: "pitch",
        name: "Pitch",
        brand: Color(light: 0x0E8A53, dark: 0x34D399),
        screen: Color(light: 0xEFF4F0, dark: 0x0A0F0C),
        card: Color(light: 0xFFFFFF, dark: 0x14201A),
        cardElevated: Color(light: 0xFFFFFF, dark: 0x1E2B23),
        hairline: Color(light: 0xDBE7DF, dark: 0x27342C)
    )

    /// Steel blue on true neutrals — calm and professional.
    static let graphite = Theme(
        id: "graphite",
        name: "Graphite",
        brand: Color(light: 0x0284C7, dark: 0x38BDF8),
        screen: Color(light: 0xF3F4F6, dark: 0x0C0D0F),
        card: Color(light: 0xFFFFFF, dark: 0x1B1C1F),
        cardElevated: Color(light: 0xFFFFFF, dark: 0x26272B),
        hairline: Color(light: 0xE5E7EB, dark: 0x2E3034)
    )

    /// Warm amber on toasted neutrals — energetic.
    static let sunset = Theme(
        id: "sunset",
        name: "Sunset",
        brand: Color(light: 0xEA580C, dark: 0xFB923C),
        screen: Color(light: 0xF8F3EF, dark: 0x12100E),
        card: Color(light: 0xFFFFFF, dark: 0x211C18),
        cardElevated: Color(light: 0xFFFFFF, dark: 0x2C2621),
        hairline: Color(light: 0xEBE2DA, dark: 0x342C25)
    )

    /// All selectable themes, in display order.
    static let all: [Theme] = [.indigo, .pitch, .graphite, .sunset]
    /// The default theme.
    static let standard = Theme.indigo

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .standard
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .standard
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Owns the selected theme and persists it. Injected at the app root so a change
/// re-renders the tree, re-evaluating `.environment(\.theme, …)` and `.tint(…)`.
@MainActor
final class ThemeManager: ObservableObject {
    private static let storageKey = "selectedThemeID"

    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.storageKey) }
    }

    var current: Theme { Theme.named(selectedID) }

    init(defaults: UserDefaults = .standard) {
        selectedID = defaults.string(forKey: Self.storageKey) ?? Theme.standard.id
    }

    func select(_ theme: Theme) {
        selectedID = theme.id
    }
}
