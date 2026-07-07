import Foundation

/// Drives the generic form runner: holds the in-progress answers for one
/// `FormTemplate` and turns them into a `FormInstance` on save. This is what
/// makes the engine *usable* — one screen renders any template, so a new scored
/// flow needs a template, not a bespoke form + view model.
@MainActor
final class FormRunnerViewModel: ObservableObject {
    let template: FormTemplate
    let subject: FormSubject
    let contextRef: FormContextRef
    let isEditing: Bool

    /// Working answers, keyed by field key. Absent = unanswered.
    @Published var draft: [String: FormAnswer]

    private let instanceID: UUID
    private let submittedAt: Date
    /// Preserved from an edited instance (this basic runner doesn't expose the
    /// freeform escape-hatch note, but it must not drop it on save).
    private let note: String

    init(template: FormTemplate, subject: FormSubject,
         contextRef: FormContextRef = .standalone, existing: FormInstance? = nil) {
        self.template = template
        self.subject = subject
        self.contextRef = existing?.contextRef ?? contextRef
        if let existing {
            instanceID = existing.id
            submittedAt = existing.submittedAt
            note = existing.note
            draft = Dictionary(existing.answers.map { ($0.fieldKey, $0) }, uniquingKeysWith: { a, _ in a })
            isEditing = true
        } else {
            instanceID = UUID()
            submittedAt = Date()
            note = ""
            draft = [:]
            isEditing = false
        }
    }

    // MARK: - Typed bindings into `draft`

    /// A 1...5 scale (0 = cleared/unrecorded, so it stores no answer).
    func scaleValue(_ key: String) -> Int { draft[key]?.intValue ?? 0 }
    func setScale(_ key: String, _ value: Int) {
        draft[key] = value == 0 ? nil : FormAnswer(fieldKey: key, number: Double(value))
    }

    /// A count (0 = unrecorded, matching the structs it replaces).
    func numberValue(_ key: String) -> Int { draft[key]?.intValue ?? 0 }
    func setNumber(_ key: String, _ value: Int) {
        draft[key] = value == 0 ? nil : FormAnswer(fieldKey: key, number: Double(value))
    }

    /// A yes/no field; `nil` = not asked.
    func boolValue(_ key: String) -> Bool? { draft[key]?.flag }
    func setBool(_ key: String, _ value: Bool?) {
        draft[key] = value.map { FormAnswer(fieldKey: key, flag: $0) }
    }

    /// Freeform / select text (empty = unrecorded).
    func textValue(_ key: String) -> String { draft[key]?.text ?? "" }
    func setText(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        draft[key] = trimmed.isEmpty ? nil : FormAnswer(fieldKey: key, text: value)
    }

    // MARK: - Result

    /// The instance as currently drafted, answers in template field order.
    var instance: FormInstance {
        let answers = template.orderedFields.compactMap { draft[$0.key] }.filter { !$0.isEmpty }
        return FormInstance(
            id: instanceID,
            templateID: template.id,
            templateVersion: template.version,
            context: template.context,
            subject: subject,
            contextRef: contextRef,
            submittedAt: submittedAt,
            answers: answers,
            note: note
        )
    }

    /// Persists the drafted instance. Empty drafts are dropped by the store, so
    /// an opened-then-untouched form never creates a row.
    func save(into store: AppStore) {
        store.saveFormInstance(instance)
    }
}
