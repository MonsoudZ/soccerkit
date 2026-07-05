import SwiftUI

/// A transient "Deleted X · Undo" banner driven by `AppStore.undoMessage`. It
/// auto-dismisses after a few seconds; tapping Undo reverts the last delete.
private struct UndoBannerModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = store.undoMessage {
                    banner(message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.undoMessage)
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: Spacing.md)
            Button("Undo") { store.undoLastDelete() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        .shadow(color: Elevation.cardColor, radius: Elevation.cardRadius, y: Elevation.cardYOffset)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.md)
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            store.dismissUndo()
        }
    }
}

extension View {
    /// Overlays a transient undo banner for the most recent delete.
    func undoBanner() -> some View {
        modifier(UndoBannerModifier())
    }
}
