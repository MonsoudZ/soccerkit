import Foundation

// MARK: - Vocabulary

/// The moment/purpose a form is filled in. Denormalized onto `FormInstance` so
/// the common "all pre-game responses for this athlete" query needs no template
/// join. Raw values are snake_case so they map 1:1 onto the eventual Rails
/// backend column.
enum FormContext: String, CaseIterable, Identifiable, Codable {
    case tryout
    case preGame = "pre_game"
    case postGame = "post_game"
    case development
    case movement
    case coachReview = "coach_review"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tryout: return "Tryout"
        case .preGame: return "Pre-Match"
        case .postGame: return "Post-Match"
        case .development: return "Development"
        case .movement: return "Movement"
        case .coachReview: return "Coach Review"
        }
    }
}

/// What a filled-in form is *about*. `athlete`/`team` carry the subject's id;
/// `coach` carries none yet (a solo coach has no server-side `Person` row —
/// when accounts land it gains an id, without a schema change here).
enum SubjectType: String, CaseIterable, Identifiable, Codable {
    case athlete
    case coach
    case team

    var id: String { rawValue }
}

/// The shape of a single answerable field. Mirrors the doc's
/// `kind ∈ {scale, bool, number, text, select}`.
enum FieldKind: String, CaseIterable, Identifiable, Codable {
    case scale   // a bounded integer, e.g. 1...5
    case bool    // yes/no (nil = not asked)
    case number  // an unbounded count, e.g. minutes/goals
    case text    // freeform
    case select  // one of `config.options`

    var id: String { rawValue }
}

// MARK: - Template

/// Per-field configuration. Every property is optional so the shape can grow
/// without breaking already-persisted templates.
struct FormFieldConfig: Hashable, Codable {
    /// Inclusive lower bound for `scale`/`number`.
    var min: Int?
    /// Inclusive upper bound for `scale`/`number`.
    var max: Int?
    /// For `scale`: whether a higher value is a *better* outcome. Drives the
    /// composite-score direction (readiness averages "higher is better" scales).
    var higherIsBetter: Bool?
    /// Allowed values for a `select` field.
    var options: [String]?

    init(min: Int? = nil, max: Int? = nil, higherIsBetter: Bool? = nil, options: [String]? = nil) {
        self.min = min
        self.max = max
        self.higherIsBetter = higherIsBetter
        self.options = options
    }

    static let none = FormFieldConfig()
    static func scale(min: Int = 1, max: Int = 5, higherIsBetter: Bool = true) -> FormFieldConfig {
        FormFieldConfig(min: min, max: max, higherIsBetter: higherIsBetter)
    }
    static func number(min: Int? = 0, max: Int? = nil) -> FormFieldConfig {
        FormFieldConfig(min: min, max: max)
    }
    static func select(_ options: [String]) -> FormFieldConfig {
        FormFieldConfig(options: options)
    }

    enum CodingKeys: String, CodingKey { case min, max, higherIsBetter, options }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        min = try c.decodeIfPresent(Int.self, forKey: .min)
        max = try c.decodeIfPresent(Int.self, forKey: .max)
        higherIsBetter = try c.decodeIfPresent(Bool.self, forKey: .higherIsBetter)
        options = try c.decodeIfPresent([String].self, forKey: .options)
    }
}

/// One question in a template. Identified by a stable string `key` (e.g.
/// "sleep"), unique within its template, so answers reference it by name and
/// survive template id churn.
struct FormField: Identifiable, Hashable, Codable {
    let key: String
    var label: String
    var kind: FieldKind
    var position: Int
    var config: FormFieldConfig

    var id: String { key }

    init(key: String, label: String, kind: FieldKind, position: Int, config: FormFieldConfig = .none) {
        self.key = key
        self.label = label
        self.kind = kind
        self.position = position
        self.config = config
    }

    enum CodingKeys: String, CodingKey { case key, label, kind, position, config }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(FieldKind.self, forKey: .kind)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        config = try c.decodeIfPresent(FormFieldConfig.self, forKey: .config) ?? .none
    }
}

/// A reusable questionnaire definition — the doc's
/// `(organization_id, context, name, subject_type, version)` plus its ordered
/// fields. `organizationID == nil` means a personal template (a solo coach's,
/// or one carried between clubs); a club later owns standardized templates by
/// setting it. `isBuiltIn` marks the seeded catalog templates that ship in code.
struct FormTemplate: Identifiable, Hashable, Codable {
    let id: UUID
    var organizationID: UUID?
    var context: FormContext
    var subjectType: SubjectType
    var name: String
    var version: Int
    var fields: [FormField]
    var isBuiltIn: Bool

    init(id: UUID, organizationID: UUID? = nil, context: FormContext, subjectType: SubjectType,
         name: String, version: Int = 1, fields: [FormField], isBuiltIn: Bool = false) {
        self.id = id
        self.organizationID = organizationID
        self.context = context
        self.subjectType = subjectType
        self.name = name
        self.version = version
        self.fields = fields.sorted { $0.position < $1.position }
        self.isBuiltIn = isBuiltIn
    }

    /// Fields in display order.
    var orderedFields: [FormField] { fields.sorted { $0.position < $1.position } }

    /// The `scale` fields — the ones a composite readiness/effort score averages.
    var scaleFields: [FormField] { orderedFields.filter { $0.kind == .scale } }

    func field(for key: String) -> FormField? { fields.first { $0.key == key } }

    enum CodingKeys: String, CodingKey {
        case id, organizationID, context, subjectType, name, version, fields, isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        organizationID = try c.decodeIfPresent(UUID.self, forKey: .organizationID)
        context = try c.decode(FormContext.self, forKey: .context)
        subjectType = try c.decode(SubjectType.self, forKey: .subjectType)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fields = try c.decodeIfPresent([FormField].self, forKey: .fields) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

// MARK: - Instance

/// Who/what a filled-in form is about. A struct (not an enum with associated
/// values) so it stays trivially Codable and forward-compatible.
struct FormSubject: Hashable, Codable {
    var type: SubjectType
    /// Player id for `athlete`, team id for `team`, `nil` for the solo `coach`.
    var id: UUID?

    static func athlete(_ id: UUID) -> FormSubject { FormSubject(type: .athlete, id: id) }
    static func team(_ id: UUID) -> FormSubject { FormSubject(type: .team, id: id) }
    static let coach = FormSubject(type: .coach, id: nil)

    enum CodingKeys: String, CodingKey { case type, id }

    init(type: SubjectType, id: UUID?) { self.type = type; self.id = id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(SubjectType.self, forKey: .type)
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
    }
}

/// A nullable polymorphic pointer to the thing a form was filled in *for* — the
/// game, session, or tryout it belongs to. `standalone` = not tied to any event.
struct FormContextRef: Hashable, Codable {
    enum Kind: String, CaseIterable, Codable {
        case game, session, event, tryout, standalone
    }
    var kind: Kind
    var id: UUID?

    static func game(_ id: UUID) -> FormContextRef { FormContextRef(kind: .game, id: id) }
    static func session(_ id: UUID) -> FormContextRef { FormContextRef(kind: .session, id: id) }
    static func event(_ id: UUID) -> FormContextRef { FormContextRef(kind: .event, id: id) }
    static let standalone = FormContextRef(kind: .standalone, id: nil)

    enum CodingKeys: String, CodingKey { case kind, id }

    init(kind: Kind, id: UUID?) { self.kind = kind; self.id = id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .standalone
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
    }
}

/// A single normalized answer — the doc's
/// `(field_id, numeric_value, bool_value, text_value)`, keyed here by the
/// field's stable `key`. One typed value per row, not a JSON blob, so scores
/// stay averageable/groupable when this reaches Postgres.
struct FormAnswer: Hashable, Codable {
    var fieldKey: String
    /// Set for `scale`/`number` fields (stored as Double so it averages cleanly).
    var number: Double?
    /// Set for `bool` fields.
    var flag: Bool?
    /// Set for `text`/`select` fields.
    var text: String?

    init(fieldKey: String, number: Double? = nil, flag: Bool? = nil, text: String? = nil) {
        self.fieldKey = fieldKey
        self.number = number
        self.flag = flag
        self.text = text
    }

    static func scale(_ key: String, _ value: Int) -> FormAnswer { FormAnswer(fieldKey: key, number: Double(value)) }
    static func number(_ key: String, _ value: Int) -> FormAnswer { FormAnswer(fieldKey: key, number: Double(value)) }
    static func bool(_ key: String, _ value: Bool) -> FormAnswer { FormAnswer(fieldKey: key, flag: value) }
    static func text(_ key: String, _ value: String) -> FormAnswer { FormAnswer(fieldKey: key, text: value) }

    /// The numeric value as an `Int`, when one was recorded.
    var intValue: Int? { number.map { Int($0.rounded()) } }

    /// True when the answer carries no recorded value (so blank answers can be
    /// dropped rather than stored).
    var isEmpty: Bool {
        number == nil && flag == nil
            && (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    enum CodingKeys: String, CodingKey { case fieldKey, number, flag, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fieldKey = try c.decode(String.self, forKey: .fieldKey)
        number = try c.decodeIfPresent(Double.self, forKey: .number)
        flag = try c.decodeIfPresent(Bool.self, forKey: .flag)
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }
}

/// One filled-out response — the spine of the evaluation engine. Every scored
/// moment in the product (tryout, pre/post-game, development, movement, coach
/// self-review) is a `FormInstance` over some template, differing only in which
/// template and subject. `templateVersion` is captured at fill time so later
/// edits to the template never rewrite historical answers (soft-immutability).
struct FormInstance: Identifiable, Hashable, Codable {
    let id: UUID
    var templateID: UUID
    var templateVersion: Int
    /// Denormalized from the template for join-free filtering.
    var context: FormContext
    var subject: FormSubject
    var contextRef: FormContextRef
    var submittedAt: Date
    /// The person who filled it in; `nil` until server-side accounts exist.
    var submittedBy: UUID?
    var answers: [FormAnswer]
    /// Freeform escape hatch for genuinely unstructured extras (the jsonb the
    /// doc keeps beside the normalized answers).
    var note: String

    init(id: UUID = UUID(), templateID: UUID, templateVersion: Int = 1, context: FormContext,
         subject: FormSubject, contextRef: FormContextRef = .standalone, submittedAt: Date = Date(),
         submittedBy: UUID? = nil, answers: [FormAnswer] = [], note: String = "") {
        self.id = id
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.context = context
        self.subject = subject
        self.contextRef = contextRef
        self.submittedAt = submittedAt
        self.submittedBy = submittedBy
        self.answers = answers
        self.note = note
    }

    func answer(for key: String) -> FormAnswer? { answers.first { $0.fieldKey == key } }
    func number(for key: String) -> Double? { answer(for: key)?.number }
    func intValue(for key: String) -> Int? { answer(for: key)?.intValue }
    func flag(for key: String) -> Bool? { answer(for: key)?.flag }
    func text(for key: String) -> String? { answer(for: key)?.text }

    /// True when nothing was recorded, so an untouched form can be discarded.
    var isEmpty: Bool {
        answers.allSatisfy(\.isEmpty)
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, templateID, templateVersion, context, subject, contextRef, submittedAt, submittedBy, answers, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decode(UUID.self, forKey: .templateID)
        templateVersion = try c.decodeIfPresent(Int.self, forKey: .templateVersion) ?? 1
        context = try c.decode(FormContext.self, forKey: .context)
        subject = try c.decode(FormSubject.self, forKey: .subject)
        contextRef = try c.decodeIfPresent(FormContextRef.self, forKey: .contextRef) ?? .standalone
        submittedAt = try c.decodeIfPresent(Date.self, forKey: .submittedAt) ?? Date()
        submittedBy = try c.decodeIfPresent(UUID.self, forKey: .submittedBy)
        answers = try c.decodeIfPresent([FormAnswer].self, forKey: .answers) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}
