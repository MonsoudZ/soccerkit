import SwiftUI

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.headline, design: .rounded))
            .padding(.top, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Full-screen placeholder for an empty or missing screen, with an optional
/// supporting message and a primary call-to-action button.
///
/// Scrollable despite having nothing to scroll: a screen that shows this is one
/// where the coach most wants to pull down and check whether the fixture their
/// co-coach added has arrived yet, and `.refreshable` needs a scroll view to
/// attach the gesture to. `containerRelativeFrame` keeps the content centred,
/// which a plain `maxHeight: .infinity` no longer does once it's inside a
/// scroll view that sizes to its content.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            content
                .containerRelativeFrame(.vertical, alignment: .center)
        }
        .screenBackground()
    }

    private var content: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 92, height: 92)
                .background(Circle().fill(Color.brand.opacity(0.12)))

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

/// Compact placeholder for an empty result inside a populated list (for example,
/// when a search or filter matches nothing).
struct InlineEmptyView: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.brand.opacity(0.12)))
            Text(title)
                .font(.subheadline.weight(.medium))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .background(.tint.opacity(0.14))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
