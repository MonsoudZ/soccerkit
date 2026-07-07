import SwiftUI

/// Renders any `FormTemplate` as an editable form and saves a `FormInstance`.
/// One control per `FieldKind`, so every current and future evaluation flow —
/// pre/post-game, development, tryout, coach review — is this single screen
/// parameterized by a template.
struct FormRunnerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FormRunnerViewModel

    init(template: FormTemplate, subject: FormSubject,
         contextRef: FormContextRef = .standalone, existing: FormInstance? = nil) {
        _viewModel = StateObject(wrappedValue: FormRunnerViewModel(
            template: template, subject: subject, contextRef: contextRef, existing: existing))
    }

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.template.orderedFields) { field in
                    fieldRow(field)
                }
            } footer: {
                Text(viewModel.template.context.displayName + " • " + viewModel.template.name)
            }
        }
        .themedList()
        .navigationTitle(viewModel.isEditing ? "Edit \(viewModel.template.name)" : viewModel.template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(into: store)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: FormField) -> some View {
        switch field.kind {
        case .scale:
            HStack {
                Text(field.label)
                Spacer()
                EffortStars(rating: Binding(
                    get: { viewModel.scaleValue(field.key) },
                    set: { viewModel.setScale(field.key, $0) }
                ))
            }
        case .number:
            Stepper(value: Binding(
                get: { viewModel.numberValue(field.key) },
                set: { viewModel.setNumber(field.key, $0) }
            ), in: 0...200) {
                LabeledContent(field.label, value: "\(viewModel.numberValue(field.key))")
            }
        case .bool:
            BoolFieldRow(label: field.label, selection: Binding(
                get: { viewModel.boolValue(field.key) },
                set: { viewModel.setBool(field.key, $0) }
            ))
        case .text:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(field.label, text: Binding(
                    get: { viewModel.textValue(field.key) },
                    set: { viewModel.setText(field.key, $0) }
                ), axis: .vertical)
                .lineLimit(1...5)
            }
        case .select:
            Picker(field.label, selection: Binding(
                get: { viewModel.textValue(field.key) },
                set: { viewModel.setText(field.key, $0) }
            )) {
                Text("—").tag("")
                ForEach(field.config.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }
}

/// A tri-state yes / no / unset control for a `bool` field.
private struct BoolFieldRow: View {
    let label: String
    @Binding var selection: Bool?

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: Spacing.md) {
                choice("Yes", true)
                choice("No", false)
                choice("—", nil)
            }
        }
    }

    private func choice(_ text: String, _ value: Bool?) -> some View {
        Button(text) { selection = value }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(selection == value ? .bold : .regular))
            .foregroundStyle(selection == value ? Color.brand : Color.secondary)
    }
}

/// Compact read-only summary of a filled-in evaluation, for history lists.
struct FormInstanceRow: View {
    let instance: FormInstance
    let template: FormTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(template?.name ?? instance.context.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let score = compositeScore {
                    Label(String(format: "%.1f", score), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color.caution)
                        .labelStyle(.titleAndIcon)
                }
            }
            HStack(spacing: Spacing.sm) {
                Text(instance.submittedAt.formatted(date: .abbreviated, time: .omitted))
                Text("•")
                Text("\(answeredCount) recorded")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var compositeScore: Double? {
        guard let template else { return nil }
        return FormEngine.scaleMean(of: instance, using: template)
    }

    private var answeredCount: Int {
        instance.answers.filter { !$0.isEmpty }.count
    }

    private var accessibilityLabel: String {
        var parts = [template?.name ?? instance.context.displayName,
                     instance.submittedAt.formatted(date: .abbreviated, time: .omitted)]
        if let score = compositeScore { parts.append("average \(String(format: "%.1f", score)) of 5") }
        return parts.joined(separator: ", ")
    }
}
