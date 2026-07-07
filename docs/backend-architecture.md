# SoccerCoachKit — Backend Architecture (Rails + PostgreSQL)

*Scoping draft. This is the server that the iOS client's schema was designed against. Every table below maps to a Swift model already shipped in `SoccerCoachKit/Models` and serialized by `SyncRecords`. The client keeps working on CloudKit until this lands; the cutover is additive.*

---

## 0. Why a backend, and why now

The client-side seams are complete: `Organization`/`OrgMembership`/`OrgRole`, `Person`/`UserAccount`, time-bounded `RosterMembership`, the generic evaluation engine, and polymorphic `ShareGrant` all exist, migrate losslessly, and sync per-record. That was the cheap part.

The backend is the point the architecture doc flagged as unavoidable:

> **The role hierarchy ends the no-backend option.** CKShare does peer-to-peer record sharing; it cannot express "a director oversees coaches who each see only their teams, and parents see only their child." That's multi-tenant role-based access control, which needs a server.

So this is not another Swift migration — it's a new service. Two hard requirements drive every decision below:

1. **Multi-tenant RBAC.** Every read and write is scoped to an organization and gated by the caller's roles in that org. The permission matrix already exists in the client (`Permissions.swift`); the server is the *authority* for it.
2. **Server-side entitlement enforcement from day one.** Premium gating lives on write endpoints, not the client. Client lockout softens to read-only; the server is the source of truth. (The Intentia lesson, applied preventively.)

**Stack:** Rails 7 API-only + PostgreSQL 15+. The iOS app becomes an API client with a local cache — its `PersistenceService` protocol swaps from *source of truth* to *cache + sync*, and feature code barely changes.

---

## 1. Model → table mapping (the sync contract)

Each shipped Swift model becomes one table. Names are snake_case; the Swift `context`/`kind`/`role` raw values were already chosen snake_case for this reason (`pre_game`, `coach_review`, etc.).

| Swift model (`SoccerCoachKit/Models`) | Table | Notes |
|---|---|---|
| `Organization` (`OrgKind`) | `organizations` | tenant boundary; `kind ∈ {personal, club}` |
| `Person` | `people` | identity/contact/medical; the human |
| `UserAccount` | `user_accounts` | Sign in with Apple; `person_id` nullable |
| `OrgMembership` (`OrgRole`) | `org_memberships` | `(person, org, roles[])` — the RBAC join |
| `Team` | `teams` | `organization_id` not null |
| `RosterMembership` (`RosterStatus`) | `roster_memberships` | time-bounded; `left_on` nullable = active |
| `Player` | `players` | `person_id` fk; jersey/position/notes (see §6 note) |
| `FormTemplate` / `FormField` | `form_templates` / `form_fields` | `organization_id` nullable = personal template |
| `FormInstance` / `FormAnswer` | `form_instances` / `form_answers` | **answers normalized, one typed row each** |
| `ShareGrant` (`ShareableType`,`ShareScope`) | `share_grants` | polymorphic `(shareable_type, shareable_id, scope)` |
| `TrainingSession`/`SessionBlock`, `Drill`, `TacticsDiagram`, `GameEvent`, `TeamEvent` | `sessions`,`session_blocks`,`drills`,`tactics_diagrams`,`game_events`,`team_events` | content; each carries `organization_id` + `author_person_id` |

Everything hangs off `organizations.id` — the single column the whole RBAC model pivots on.

---

## 2. PostgreSQL schema (DDL sketch)

UUID primary keys throughout (the client already generates UUIDs; keep them so records created offline keep their identity on upload). `citext` for emails, `timestamptz` for all times.

```sql
create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "citext";

-- ── Identity & tenancy ────────────────────────────────────────────────
create table organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        text not null check (kind in ('personal','club')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table people (
  id                          uuid primary key default gen_random_uuid(),
  name                        text not null,
  guardian                    text not null default '',
  guardian_phone              text not null default '',
  guardian_email              citext not null default '',
  secondary_contact_name      text not null default '',
  secondary_contact_phone     text not null default '',
  emergency_contact_name      text not null default '',
  emergency_contact_phone     text not null default '',
  emergency_contact_relation  text not null default '',
  allergies                   text not null default '',
  medical_notes               text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table user_accounts (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid references people(id) on delete set null,   -- nullable owner
  apple_user_id  text not null unique,
  display_name   text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- roles as a join table (one row per role) OR a Postgres array. The client
-- models roles as a Set<OrgRole>; an array column mirrors that 1:1 and keeps
-- membership a single row. Use a CHECK-constrained text[] with a GIN index.
create table org_memberships (
  id               uuid primary key default gen_random_uuid(),
  person_id        uuid not null references people(id) on delete cascade,
  organization_id  uuid not null references organizations(id) on delete cascade,
  roles            text[] not null default '{}',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (person_id, organization_id),
  constraint valid_roles check (
    roles <@ array['admin','director','coach','parent','player']::text[]
  )
);
create index on org_memberships using gin (roles);
create index on org_memberships (organization_id);

-- ── Teams & movement ──────────────────────────────────────────────────
create table teams (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references organizations(id) on delete cascade,
  name                   text not null,
  age_group              text not null,
  season                 text not null,
  accent_name            text not null default 'Teal',
  period_format          text not null default 'Halves',
  default_minimum_minutes int not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create index on teams (organization_id);

create table players (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references people(id) on delete cascade,
  number     int  not null default 0,
  position   text not null default 'MID',
  notes      text not null default '',
  min_minutes_override int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table roster_memberships (
  id               uuid primary key default gen_random_uuid(),
  player_id        uuid not null references players(id) on delete cascade,
  team_id          uuid not null references teams(id) on delete cascade,
  jersey_number    int,
  position         text,
  joined_on        date,
  left_on          date,                -- null = active
  status           text not null default 'active'
                     check (status in ('active','guest','injured','inactive')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on roster_memberships (team_id) where left_on is null;   -- active roster
create index on roster_memberships (player_id);

-- ── Evaluation engine (the moat) ──────────────────────────────────────
create table form_templates (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid references organizations(id) on delete cascade,  -- null = personal
  context          text not null,        -- pre_game | post_game | development | tryout | movement | coach_review
  subject_type     text not null,        -- athlete | coach | team
  name             text not null,
  version          int  not null default 1,
  is_built_in      boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table form_fields (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references form_templates(id) on delete cascade,
  key          text not null,            -- stable, e.g. "sleep"
  label        text not null,
  kind         text not null,            -- scale | bool | number | text | select
  position     int  not null default 0,
  config       jsonb not null default '{}',
  unique (template_id, key)
);

create table form_instances (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid not null references form_templates(id),
  template_version  int  not null default 1,
  context           text not null,
  subject_type      text not null,       -- athlete | coach | team
  subject_id        uuid,                -- person_id or team_id (nullable for future coach)
  context_ref_kind  text,                -- game | session | event | tryout | standalone
  context_ref_id    uuid,
  submitted_by      uuid references people(id),
  submitted_at      timestamptz not null default now(),
  note              text not null default '',
  organization_id   uuid not null references organizations(id) on delete cascade
);
create index on form_instances (subject_type, subject_id, context);
create index on form_instances (organization_id);

-- Normalized, NOT jsonb: the whole point is AVG / GROUP BY over scored fields
-- ("poor sleep → poor game"). One typed value per row.
create table form_answers (
  id             uuid primary key default gen_random_uuid(),
  instance_id    uuid not null references form_instances(id) on delete cascade,
  field_key      text not null,
  numeric_value  double precision,       -- scale / number
  bool_value     boolean,                -- bool
  text_value     text,                   -- text / select
  unique (instance_id, field_key)
);
create index on form_answers (field_key, numeric_value);

-- ── Sharing ───────────────────────────────────────────────────────────
create table share_grants (
  id               uuid primary key default gen_random_uuid(),
  shareable_type   text not null,        -- session | drill | diagram | form_template
  shareable_id     uuid not null,
  scope            text not null default 'private'
                     check (scope in ('private','team','org','link')),
  organization_id  uuid not null references organizations(id) on delete cascade,
  granted_by       uuid references people(id),
  expires_at       timestamptz,
  created_at       timestamptz not null default now(),
  unique (shareable_type, shareable_id, organization_id)
);
create index on share_grants (organization_id, shareable_type) where scope = 'org';

-- ── Content (carried over, each gains organization_id + author_person_id) ──
-- sessions, session_blocks, drills, tactics_diagrams, game_events, team_events
-- follow the same shape: uuid pk, organization_id fk, author_person_id fk,
-- created_at/updated_at, plus their existing columns. Omitted for brevity.
```

### Schema decisions worth defending
- **`form_answers` is normalized, not jsonb.** This is the doc's explicit call and the reason the engine exists — readiness means, effort trends, tryout rankings are `AVG`/`GROUP BY` over `numeric_value`. `form_fields.config` stays jsonb (genuinely variable shape); the *scored answers* do not.
- **`roles` as a `text[]` with a CHECK + GIN index** mirrors the client's `Set<OrgRole>` exactly and keeps a membership one row. A `role_assignments` child table is the alternative if you ever need per-role metadata (granted_at, granted_by per role); start with the array.
- **`roster_memberships.left_on` nullable = active**, indexed partially — the "current roster" query is `where team_id = ? and left_on is null`, matching the client's `isActive`.
- **`share_grants` is polymorphic** by `(shareable_type, shareable_id)`. No per-type join tables. The club library is one query: `where organization_id = ? and scope = 'org' and shareable_type = ?`.
- **`organization_id` denormalized onto leaf tables** (`form_instances`, content) even though it's derivable — it's the RBAC scope column and every policy filters on it, so it must be indexed and local, not a 3-join lookup.

---

## 3. Authorization (RBAC) — the server is the authority

Roles come from `org_memberships.roles` for the `(current_person, target_organization)` pair. The client's `Permissions` matrix (`Capability → Set<OrgRole>`) is re-implemented server-side as the *enforced* policy (e.g. Pundit policies), never trusted from the client.

Coarse capability → roles (mirrors `Permissions.swift`):

| Capability | Roles |
|---|---|
| manage org / billing / seats | admin |
| standardize templates, see every team | admin, director |
| run sessions, evaluate, move players, see shared library | admin, director, coach |
| see a specific athlete's full record | admin, director, coach, parent, player |
| fill pre/post-game check-in | parent, player |

**Scope qualifiers** (`own teams` / `own child` / `self`) are enforced at the query layer, not the capability layer:
- **coach → own teams:** `teams` the coach has a coaching `roster`/assignment to (a `coach_assignments` table, or reuse `org_memberships` + a team-scoped grant). Directors/admins skip the filter (whole org).
- **parent → own child:** a `guardianships` table `(guardian_person_id, child_person_id)` — the Phase-5 seam, not yet in the client. Parent queries join through it.
- **player → self:** `submitted_by = current_person` / `subject_id = current_person`.

Every controller: authenticate → resolve org context → `authorize` the capability → **scope the relation** to what the caller may see. A missing scope is the classic multi-tenant leak; make the base scope mandatory (a default `policy_scope` on every index).

---

## 4. API contract (REST, versioned `/v1`)

JSON:API-ish. All requests carry `Authorization: Bearer <jwt>`; most carry an `X-Org-Id` (or `/orgs/:org_id/...` nesting) to fix the tenant.

### Auth
```
POST /v1/auth/apple          # {identity_token, authorization_code, full_name?}
    → verifies Apple token, upserts user_accounts, mints app JWT
    → {token, person, memberships:[{organization, roles}]}
POST /v1/auth/refresh
```
Sign in with Apple stays the client flow; the server verifies the identity token, creates/links the `user_account`, and on first sign-in bootstraps the **personal org + owner Person + admin/director/coach membership** — the server-side equivalent of the client's `ensureOwner`.

### Core resources (all org-scoped, all RBAC-gated)
```
GET    /v1/orgs/:org_id/teams
POST   /v1/orgs/:org_id/teams
GET    /v1/teams/:id/roster                 # active roster_memberships → players → people
POST   /v1/players/:id/move                 # {to_team_id, on: date}  → ends+opens memberships
POST   /v1/players/:id/guest                # {team_id}               → concurrent membership

GET    /v1/orgs/:org_id/form_templates      # built-ins + org + personal
POST   /v1/form_instances                   # {template_id, subject, context_ref, answers:[...]}
GET    /v1/people/:id/form_instances?context=pre_game
GET    /v1/teams/:id/readiness              # server-side AVG over form_answers (the trend/squad board)

POST   /v1/share_grants                     # {shareable_type, shareable_id, scope, expires_at?}
GET    /v1/orgs/:org_id/library?type=drill  # scope='org' grants → shareables
```

### Sync (the important one)
The client's `SyncRecords` already models the whole store as typed, id'd, diffable records. Mirror that as a **delta sync** endpoint rather than N REST calls:

```
GET  /v1/sync?since=<cursor>
    → { records:[{type, id, org_id, updated_at, payload}], deletes:[{type,id}], cursor }
POST /v1/sync
    → { upserts:[{type, id, payload, base_version}], deletes:[{type,id}] }
    → per-record: applied | conflict(server_version)
```
- `type` is the `SyncRecordType` raw value already defined client-side (`Team`, `Player`, `RosterMembership`, `Person`, `OrgMembership`, `ShareGrant`, `FormInstance`, …).
- **Conflict resolution:** the client already carries a monotonic `dataVersion`; per record, last-writer-wins by `updated_at`, with `base_version` optimistic-concurrency on writes (reject + return server copy on mismatch, same as CloudKit's record-level merge today).
- **Entitlement + RBAC on `POST /sync`:** every upsert is authorized and org-scoped server-side. A client cannot write a record into an org it lacks a role in, cannot escalate its own `org_memberships.roles`, and premium-gated writes are rejected here — not on the client.

---

## 5. How the iOS client swaps over (no big-bang)

The `PersistenceService` protocol is the seam:

1. **Add `APISyncService`** alongside `CloudKitSyncService`, implementing the same push/pull shape (`SyncRecords` → `/v1/sync`). The `AppStore` already diffs and applies records; point it at the API instead of CKSyncEngine.
2. **`UserDefaultsPersistenceService` stays** as the offline cache (game day on a dead-signal sideline still works). Source of truth moves server-side; the local store is a write-through cache with a pending-upload queue.
3. **Cutover per environment, not per feature:** run CloudKit and API in parallel behind a flag; migrate a coach's data once (upload their local snapshot via `/sync`), then flip them to API-authoritative and retire their CloudKit zone. New sign-ups go straight to API.
4. **Retire CloudKit** once all active coaches are migrated. `SyncRecords` is unit-tested and unchanged — only the transport swaps.

Server-side entitlement enforcement means the client's premium gating becomes advisory UI; the write endpoints are the real gate from day one.

---

## 6. Open items to resolve before building

- **`players` vs `people` normalization.** The client currently keeps a 1:1 `Player`↔`Person` (additive seam). The backend can either mirror that (a `players` table with `person_id`, as above) or take the doc's end state now (dissolve `players` into `people` + `roster_memberships`, jersey/position on the membership). **Recommendation:** mirror the client 1:1 first so the sync contract is trivial, then normalize server-side once the client dissolves `Player`.
- **`guardianships` + player self-accounts** (`Person` ↔ `UserAccount` for older players) — the Phase-5 seam, not yet in the client. The RBAC scoping in §3 assumes it; add the table when the parent/player tiers ship.
- **Coach→team assignment.** "coach sees own teams" needs a `coach_assignments (person_id, team_id)` table or a team-scoped `org_membership`; the client models the solo coach as whole-org, so this is net-new for the club tier.
- **Web/Android surface.** A Rails API is what makes these possible (parents on Android hit a web link). Out of scope to build, but the API contract above is client-agnostic on purpose.

---

## 7. What to *never* build (integrate instead)

Registration / payments / league scheduling is owned by SportsEngine and GotSport. Rebuilding it is a money pit and not the moat. When a club asks: **import rosters, link out** — a `POST /v1/orgs/:id/imports` that maps their roster CSV/API into `people` + `players` + `roster_memberships`. Keep the castle to coaching, evaluation, and development — the things those platforms are bad at.
