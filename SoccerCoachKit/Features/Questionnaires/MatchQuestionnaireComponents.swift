import SwiftUI

/// A 1...5 rating row rendered as five fillable dots (0 = unrated). Tapping the
/// current value clears it back to unrated.
struct ScaleRow: View {
    let label: String
    @Binding var value: Int
    var tint: Color = .brand

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(value == 0 ? "—" : "\(value)/5")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(value == 0 ? .secondary : .primary)
                    .monospacedDigit()
            }
            HStack(spacing: Spacing.md) {
                ForEach(1...5, id: \.self) { step in
                    Circle()
                        .fill(step <= value ? tint : Color.secondary.opacity(0.16))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("\(step)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(step <= value ? .white : .secondary)
                        )
                        .contentShape(Circle())
                        .onTapGesture { value = (value == step) ? 0 : step }
                        .accessibilityLabel("\(label) \(step)")
                        .accessibilityAddTraits(step == value ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// A tri-state Yes / No / not-recorded row bound to an optional Bool.
struct YesNoRow: View {
    let label: String
    @Binding var value: Bool?

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Picker(label, selection: $value) {
                Text("—").tag(Bool?.none)
                Text("No").tag(Bool?.some(false))
                Text("Yes").tag(Bool?.some(true))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
