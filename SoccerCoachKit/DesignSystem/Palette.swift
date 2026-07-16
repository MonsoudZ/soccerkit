import SwiftUI
import UIKit

extension Color {
    /// Adaptive color from separate light/dark 24-bit RGB hex values.
    init(light: UInt32, dark: UInt32) {
        self = Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The app's color palette — the single source of truth for color. Surfaces use
/// the system grouped backgrounds so `List`/`Form` and custom `ScrollView`
/// screens stay consistent; brand and semantic colors are curated and adaptive.
extension Color {
    // MARK: Surfaces
    static let screenBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let hairline = Color(light: 0xE5E7EB, dark: 0x2C2E36)

    // MARK: Brand
    /// App brand tint (chrome/accents where no team accent applies).
    static let brand = Color(light: 0x4F46E5, dark: 0x8B8CF7)   // indigo

    // MARK: Semantic status
    static let positive = Color(light: 0x15803D, dark: 0x4ADE80)
    static let caution = Color(light: 0xB45309, dark: 0xFBBF24)
    static let critical = Color(light: 0xB91C1C, dark: 0xF87171)
    static let info = Color(light: 0x1D4ED8, dark: 0x60A5FA)
    static let rating = Color(light: 0xCA8A04, dark: 0xFACC15)
}
