#if DEBUG
import SwiftUI

/// A live gallery of the design system — colors, type, spacing, radii, and
/// components — rendered from the same tokens the app uses. Doubles as visual
/// documentation and a regression check when tokens change. Developer tooling —
/// compiled only in DEBUG so it isn't in the release binary.
struct StyleGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                colorSection
                typeSection
                radiusSection
                componentSection
            }
            .padding(Spacing.xl)
        }
        .screenBackground()
        .navigationTitle("Style Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Color").sectionHeaderStyle()
            LazyVGrid(columns: swatchColumns, spacing: Spacing.lg) {
                brandSwatch
                swatch("Positive", .positive)
                swatch("Caution", .caution)
                swatch("Critical", .critical)
                swatch("Info", .info)
                swatch("Rating", .rating)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var swatchColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 84), spacing: Spacing.lg)]
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                .fill(color)
                .frame(height: 48)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Brand reflects the active theme, so it's filled from the environment tint.
    private var brandSwatch: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                .fill(.tint)
                .frame(height: 48)
            Text("Brand")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Type").sectionHeaderStyle()
            Text("Display").font(AppFont.display)
            Text("Title").font(AppFont.title)
            Text("Headline").font(AppFont.headline)
            Text("1,024").font(AppFont.metric)
            Text("Body copy — the quick brown fox jumps over the lazy dog.")
                .font(.body)
            Text("Eyebrow label").sectionHeaderStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Radius

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Radius & Elevation").sectionHeaderStyle()
            HStack(spacing: Spacing.lg) {
                radiusChip("small", CornerRadius.small)
                radiusChip("card", CornerRadius.card)
                radiusChip("large", CornerRadius.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func radiusChip(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.tint.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 1.5)
                )
                .frame(height: 56)
            Text("\(name) · \(Int(radius))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Components

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Components").sectionHeaderStyle()

            HStack(spacing: Spacing.lg) {
                MetricTile(title: "Players", value: "14", symbol: "person.3.fill")
                MetricTile(title: "Games", value: "4", symbol: "sportscourt.fill")
            }

            TagChipsView(tags: ["Passing", "Pressing", "Set piece"])

            HStack(spacing: Spacing.md) {
                statusPill("Going", .positive)
                statusPill("Maybe", .caution)
                statusPill("Out", .critical)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func statusPill(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
#endif
