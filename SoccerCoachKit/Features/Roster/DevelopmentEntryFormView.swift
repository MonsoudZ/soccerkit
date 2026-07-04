import SwiftUI

struct DevelopmentEntryFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DevelopmentEntryFormViewModel

    init(playerID: UUID, entry: DevelopmentEntry? = nil) {
        _viewModel = StateObject(wrappedValue: DevelopmentEntryFormViewModel(playerID: playerID, entry: entry))
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
            }

            Section {
                ForEach(SkillCategory.allCases) { skill in
                    HStack {
                        Text(skill.rawValue)
                        Spacer()
                        EffortStars(rating: viewModel.ratingBinding(for: skill))
                    }
                }
            } header: {
                Text("Skill Ratings")
            } footer: {
                Text("Tap a star to rate 1–5; tap the current rating to clear it.")
            }

            Section("Notes") {
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Entry" : "New Entry")
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
}

/// Compact read-only summary of a development entry for the player detail list.
struct DevelopmentEntryRow: View {
    let entry: DevelopmentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.weight(.semibold))

            if !entry.ratedSkills.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.ratedSkills) { skill in
                        HStack(spacing: 6) {
                            Text(skill.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(stars(entry.rating(for: skill)))
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func stars(_ rating: Int) -> String {
        String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
    }
}
