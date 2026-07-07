import Foundation

/// Pure scoring and aggregation over the generic evaluation engine. This is the
/// "one query shape over `FormAnswer`, parameterized by template and subject"
/// the architecture calls for: the readiness mean, the effort trend, the tryout
/// ranking, and the development trajectory are all the *same* two operations —
/// average the scale fields of one instance, or average one field across many.
///
/// No storage or UI here, so it's fully unit-testable and ports directly to a
/// server-side `AVG`/`GROUP BY` later.
enum FormEngine {

    /// Mean of the answered `scale` fields of a single instance — the generic
    /// composite score (readiness for a pre-match check-in, and the equivalent
    /// for any other scored template). Only recorded answers count; an unrated
    /// scale contributes nothing (it is absent, not zero). `nil` when none of
    /// the scale fields were rated.
    static func scaleMean(of instance: FormInstance, using template: FormTemplate) -> Double? {
        let values = template.scaleFields.compactMap { instance.number(for: $0.key) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of one field's numeric value across many instances — the cross-
    /// instance aggregation the normalized storage is designed for (e.g. average
    /// sleep over a season, effort trend, a tryout field's ranking input).
    /// `nil` when no instance recorded that field.
    static func mean(ofField key: String, across instances: [FormInstance]) -> Double? {
        let values = instances.compactMap { $0.number(for: key) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// A field's numeric value in each instance that recorded it, oldest first —
    /// the raw series behind any trend/sparkline.
    static func series(ofField key: String, across instances: [FormInstance]) -> [(date: Date, value: Double)] {
        instances
            .compactMap { inst in inst.number(for: key).map { (date: inst.submittedAt, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Instances filtered to a subject and (optionally) a context — the spine of
    /// "this athlete's full record" and "all pre-game responses for the squad".
    static func instances(_ all: [FormInstance], for subject: FormSubject, context: FormContext? = nil) -> [FormInstance] {
        all.filter { inst in
            inst.subject.type == subject.type
                && inst.subject.id == subject.id
                && (context == nil || inst.context == context)
        }
    }

    /// Structural problems in an instance measured against its template: unknown
    /// field keys, scale values outside the configured bounds, or select values
    /// not in the allowed options. Empty means valid. Cheap client-side guard
    /// that mirrors the constraints the server will enforce.
    static func validationIssues(for instance: FormInstance, against template: FormTemplate) -> [String] {
        var issues: [String] = []
        for answer in instance.answers {
            guard let field = template.field(for: answer.fieldKey) else {
                issues.append("Unknown field '\(answer.fieldKey)'")
                continue
            }
            switch field.kind {
            case .scale, .number:
                if let value = answer.intValue {
                    if let min = field.config.min, value < min {
                        issues.append("\(field.label): \(value) below minimum \(min)")
                    }
                    if let max = field.config.max, value > max {
                        issues.append("\(field.label): \(value) above maximum \(max)")
                    }
                }
            case .select:
                if let text = answer.text, let options = field.config.options, !options.contains(text) {
                    issues.append("\(field.label): '\(text)' is not an allowed option")
                }
            case .bool, .text:
                break
            }
        }
        return issues
    }
}
