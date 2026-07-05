import SwiftUI

/// The app's type ramp. A rounded design is used for display/number styles to
/// give the product a friendly, sporty character while body text stays default
/// for legibility. Reference these instead of ad-hoc `.font(...)` calls.
enum AppFont {
    /// Large screen title (rounded, bold).
    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Section / card title.
    static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    /// Big numeric metric value (rounded, bold).
    static let metric = Font.system(.title, design: .rounded).weight(.bold)
    /// Emphasis within a row.
    static let headline = Font.headline
    /// A small, all-caps eyebrow label.
    static let eyebrow = Font.caption.weight(.semibold)
}

extension View {
    /// Section header styling: uppercased eyebrow in secondary, tracked out.
    func sectionHeaderStyle() -> some View {
        self
            .font(AppFont.eyebrow)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
