import SwiftUI

/// A settings row label with a colour-coded icon tile (à la the iOS Settings
/// app), keeping the app's IconChip language consistent on list rows.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .brand

    var body: some View {
        Label {
            Text(title)
        } icon: {
            IconChip(symbol: systemImage, accent: tint, size: 28)
        }
    }
}

/// A horizontal row of theme swatches; tapping one switches the app theme live.
struct ThemePickerRow: View {
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Theme.all) { theme in
                let isSelected = theme.id == themeManager.selectedID
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        themeManager.select(theme)
                    }
                } label: {
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(theme.brand)
                                .frame(width: 40, height: 40)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? theme.brand : Color.hairline,
                                lineWidth: isSelected ? 2.5 : 1
                            )
                            .frame(width: 48, height: 48)
                        )
                        .frame(width: 48, height: 48)

                        Text(theme.name)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Presents the system share sheet for an exported backup file.
struct SettingsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
