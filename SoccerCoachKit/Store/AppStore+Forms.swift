import Foundation

/// The evaluation engine's store surface: every scored flow the app grows from
/// here reads and writes `FormInstance`s through these intents rather than
/// adding another hand-written struct + dictionary on an entity.
extension AppStore {

    /// Built-in catalog templates (code, always current) plus any user/org
    /// templates the coach has saved. This is what the UI picks a form from.
    var allFormTemplates: [FormTemplate] {
        FormTemplateCatalog.builtIns + formTemplates
    }

    func formTemplate(id: UUID) -> FormTemplate? {
        allFormTemplates.first { $0.id == id }
    }

    /// The template an instance was filled against, at the version it captured.
    func template(for instance: FormInstance) -> FormTemplate? {
        formTemplate(id: instance.templateID)
    }

    // MARK: - Querying

    /// All responses about a subject, newest first, optionally narrowed to one
    /// context (e.g. a single athlete's pre-match check-ins).
    func formInstances(for subject: FormSubject, context: FormContext? = nil) -> [FormInstance] {
        FormEngine.instances(formInstances, for: subject, context: context)
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    /// Every response tied to a specific game/session/event.
    func formInstances(forContextRef ref: FormContextRef) -> [FormInstance] {
        formInstances.filter { $0.contextRef == ref }
    }

    // MARK: - Read-side aggregation

    /// Every evaluation about a player — engine-recorded plus the game-day
    /// check-ins still stored on `GameEvent` — projected into the engine's shape
    /// for trend/aggregation reads.
    func athleteEvaluations(_ player: Player) -> [FormInstance] {
        EvaluationReadModel.athleteInstances(
            playerID: player.id,
            developmentLog: player.developmentLog,
            games: games(inTeam: player.teamID),
            stored: formInstances
        )
    }

    /// Each player's readiness standing for a team, lowest first.
    func squadReadiness(inTeam id: UUID) -> [SquadReadinessEntry] {
        EvaluationReadModel.squadReadiness(
            players: players(inTeam: id),
            games: games(inTeam: id),
            stored: formInstances
        )
    }

    // MARK: - Mutating

    /// Saves a response, replacing any existing one with the same id. Empty
    /// responses are dropped (and removed if one existed), so an opened-then-
    /// untouched form never persists.
    func saveFormInstance(_ instance: FormInstance) {
        guard !instance.isEmpty else {
            deleteFormInstance(instance)
            return
        }
        if let index = formInstances.firstIndex(where: { $0.id == instance.id }) {
            formInstances[index] = instance
        } else {
            formInstances.append(instance)
        }
    }

    func deleteFormInstance(_ instance: FormInstance) {
        formInstances.removeAll { $0.id == instance.id }
    }

    // MARK: - Custom templates

    /// Adds or replaces a user/org-owned template. Built-in templates live in
    /// code and are never stored here, so they can't be shadowed by a save.
    func saveFormTemplate(_ template: FormTemplate) {
        guard !template.isBuiltIn else { return }
        if let index = formTemplates.firstIndex(where: { $0.id == template.id }) {
            formTemplates[index] = template
        } else {
            formTemplates.append(template)
        }
    }

    func deleteFormTemplate(_ template: FormTemplate) {
        formTemplates.removeAll { $0.id == template.id }
    }
}
