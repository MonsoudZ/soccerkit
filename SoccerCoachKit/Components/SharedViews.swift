import SwiftUI

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}

/// Full-screen placeholder for an empty or missing screen, with an optional
/// supporting message and a primary call-to-action button.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

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
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(.systemGroupedBackground))
    }
}

/// Compact placeholder for an empty result inside a populated list (for example,
/// when a search or filter matches nothing).
struct InlineEmptyView: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
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
                HStack(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.14))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
