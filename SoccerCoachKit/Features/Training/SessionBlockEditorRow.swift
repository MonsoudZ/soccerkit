import SwiftUI

struct SessionBlockEditorRow: View {
    @Binding var block: TrainingBlock
    let drill: Drill?
    let diagrams: [TacticsDiagram]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.topic.isEmpty ? drill?.title ?? "Deleted Drill" : block.topic)
                        .font(.headline)
                    Text(drill?.category.rawValue ?? "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(block.minutes) min", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Section topic", text: $block.topic, axis: .vertical)
                .lineLimit(1...3)
            Stepper("Duration \(block.minutes) min", value: $block.minutes, in: 1...90)
            Stepper("Intensity \(block.intensity) / 5", value: $block.intensity, in: 1...5)

            TextField("Part of pitch", text: $block.pitchArea)

            TextField("Block focus", text: $block.focus, axis: .vertical)
                .lineLimit(2...4)

            TextField("Description", text: $block.details, axis: .vertical)
                .lineLimit(2...5)

            if !diagrams.isEmpty {
                Picker("Field Diagram", selection: diagramBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(diagrams) { diagram in
                        Text(diagram.title).tag(Optional(diagram.id))
                    }
                }
            }

            DisclosureGroup("Positions") {
                ForEach(PlayerPosition.allCases) { position in
                    Toggle(position.rawValue, isOn: positionBinding(for: position))
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var diagramBinding: Binding<UUID?> {
        Binding {
            block.diagramID
        } set: { newValue in
            block.diagramID = newValue
        }
    }

    private func positionBinding(for position: PlayerPosition) -> Binding<Bool> {
        Binding {
            block.positions.contains(position)
        } set: { isSelected in
            if isSelected {
                if !block.positions.contains(position) {
                    block.positions.append(position)
                }
            } else {
                block.positions.removeAll { $0 == position }
            }
        }
    }
}
