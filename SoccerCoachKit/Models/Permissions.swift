import Foundation

/// A thing someone might be allowed to do within an organization. Mirrors the
/// rows of the architecture doc's §3 permission matrix.
enum Capability: String, CaseIterable, Identifiable {
    case manageOrg              // org, billing, seats
    case standardizeTemplates   // org-wide evaluation templates
    case seeEveryTeam           // every team in the org
    case runSessions            // create/run sessions, game day
    case evaluateAthletes       // tryout/dev/game evaluation
    case movePlayers            // move players between teams
    case seeAthleteRecord       // a specific athlete's full record
    case fillCheckIn            // pre/post-game check-in
    case seeSharedLibrary       // the shared org library

    var id: String { rawValue }
}

/// The role → capability matrix, as pure data. This is the whole castle's
/// permission model in one place: the solo coach's admin+director+coach light up
/// the coach-tier rows today, and the parent/player rows stay dark until those
/// tiers ship — a feature flag, not a rewrite, because the checks already exist.
///
/// Scoping qualifiers the doc notes ("own teams", "own child", "self") are
/// enforced where the data is fetched; this layer answers the coarser
/// "could this role ever do this" so callers can gate UI and endpoints.
enum Permissions {

    /// The roles allowed to perform a capability (ignoring per-record scope).
    static func roles(for capability: Capability) -> Set<OrgRole> {
        switch capability {
        case .manageOrg:
            return [.admin]
        case .standardizeTemplates, .seeEveryTeam:
            return [.admin, .director]
        case .runSessions, .evaluateAthletes, .movePlayers, .seeSharedLibrary:
            return [.admin, .director, .coach]
        case .seeAthleteRecord:
            return [.admin, .director, .coach, .parent, .player]
        case .fillCheckIn:
            return [.parent, .player]
        }
    }

    /// Whether any of the held roles grants the capability.
    static func can(_ capability: Capability, asAnyOf held: Set<OrgRole>) -> Bool {
        !held.isDisjoint(with: roles(for: capability))
    }
}
