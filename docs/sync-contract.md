# `/v1/sync` — Implementable Contract for the Go Backend

*This is the exact contract the shipped iOS client speaks. Source of truth: `SoccerCoachKit/Networking/` (`SyncWire.swift`, `BackendAPI.swift`, `APISyncService.swift`) and `SoccerCoachKit/Services/SyncRecords.swift`. The round-trip tests in `SoccerCoachKitTests/SyncWireTests.swift` are executable fixtures for the envelope.*

The design goal that makes this easy: **the server treats each record `payload` as opaque JSON.** Store it as `jsonb`, lift out only the few columns you scope/order on (`id`, `organization_id`, `updated_at`). You do **not** need to model every entity field to make sync work.

---

## 1. Endpoints (five)

All bodies are `application/json`. `/v1/sync` and `/v1/me` require `Authorization: Bearer <jwt>`; `/v1/auth/apple` and `/v1/auth/refresh` do not.

### `POST /v1/auth/apple`
Request:
```json
{ "identityToken": "<apple JWT>", "authorizationCode": "<code|null>", "fullName": "Coach Name|null" }
```
Response:
```json
{ "token": "<your session JWT>", "refreshToken": "<long-lived refresh token>", "personID": "<uuid|null>" }
```
Verify the Apple `identityToken` (JWKS from `https://appleid.apple.com/auth/keys`, audience = your bundle id, issuer = `https://appleid.apple.com`). Upsert `user_accounts` by the token's `sub` (the Apple user id). On first sign-in, bootstrap the owner (personal org + a `people` row + an `org_memberships` row with `{admin,director,coach}`) and return its `personID`. Mint your own JWT as `token`.

`refreshToken` is optional on the wire but you want to issue one: without it the client has no way to renew an expired `token`, and the coach is asked to sign in with Apple again every time the access token lapses. See `/v1/auth/refresh` below.

**The client will not proceed on a session it cannot store.** If the keychain rejects the write it reports the sign-in as failed rather than syncing on a token that reads back missing later.

### `POST /v1/auth/refresh`
Trades a valid refresh token for a fresh access token. **Unauthenticated** — the refresh token travels in the body, not the `Authorization` header, because the access token it is replacing has by definition expired.

Request:
```json
{ "refreshToken": "<the client's stored refresh token>" }
```
Response:
```json
{ "accessToken": "<new session JWT>", "refreshToken": "<new refresh token>" }
```
Both fields are required in the response. **Rotate**: revoke the presented refresh token and issue a new one, which the client stores. Return **401** if the presented token is unknown, expired, or already revoked — the client treats a 401 here as a dead session, clears both tokens, and asks the coach to sign in again; any other status is treated as a transient failure and the stored tokens are kept for a later retry.

The client calls this automatically whenever an authenticated call returns 401, then retries that call once. Concurrent callers are coalesced onto a single refresh, so you will not see two rotations racing from one device.

### `DELETE /v1/me`
Permanently deletes the authenticated account and everything it owns. Authenticated; identify the account from the bearer token. Return **2xx** (204 is fine) once the data is gone.

The client will not touch local data until this succeeds — it refuses to tell a coach their account was deleted while the server's copy survives — so a missing or failing endpoint surfaces as "Couldn't delete your account. Check your connection and try again." and nothing is removed.

### `GET /v1/sync?since=<cursor>`
Returns everything changed at/after the cursor. On the **first** sync the client sends **no** `?since` (return the full set for this account). Response:
```json
{
  "records": [ { "type": "Player", "id": "<uuid>", "payload": { … } } ],
  "deletes": [ { "type": "Player", "id": "<uuid>" } ],
  "cursor":  "<opaque server cursor>"
}
```
All three keys are optional on the wire (missing `records`/`deletes` decode as empty). Always return a `cursor`.

### `POST /v1/sync`
The client's local changes since its last cursor. Request:
```json
{
  "upserts": [ { "type": "Team", "id": "<uuid>", "payload": { … } } ],
  "deletes": [ { "type": "Player", "id": "<uuid>" } ],
  "cursor":  "<the client's current cursor|null>"
}
```
Response:
```json
{ "cursor": "<new server cursor>", "conflicts": [ { "type": "Team", "id": "<uuid>", "payload": { … } } ] }
```
`conflicts` (optional, defaults `[]`) are records where the server's copy won — the client adopts them verbatim. Return a fresh `cursor`.

---

## 2. The record envelope

```json
{ "type": "<SyncRecordType>", "id": "<string>", "payload": { …entity JSON… } }
```
- `id` is the entity UUID as a string (for `Prefs`, the literal `"prefs"`).
- `payload` is a **JSON object** — the entity's own JSON (not a string, not base64).
- Deletes are tombstones: `{ "type": …, "id": … }`.

**⚠️ `id` is not globally unique.** Two records collide across accounts by design: every install ships the same personal organization, id `0A9A0000-0000-0000-0000-000000000001`, and every install's `Prefs` record uses the literal id `"prefs"`. Scope every row by account — the unique key is `(account_id, type, id)`, as in §6 — or one coach's personal org will overwrite another's.

**`type` is one of these 16** (`SyncRecordType` raw values — exact strings):

`Organization`, `Person`, `UserAccount`, `OrgMembership`, `Team`, `RosterMembership`, `Player`, `FormTemplate`, `FormInstance`, `ShareGrant`, `Session`, `Drill`, `Diagram`, `Game`, `Event`, `Prefs`.

The client **skips record types it doesn't recognize**, so you can add types server-side without breaking older clients. `Prefs` is a singleton (`id:"prefs"`, payload `{"selectedTeamID":"<uuid>"}`).

---

## 3. Cursor + conflict model (what the client actually does)

- The client stores one **opaque cursor per account** and echoes it back. Treat it as your own monotonic marker — a `bigint` sequence or a `timestamptz`; the client never parses it.
- **Pull** (`GET`): no cursor → full set; with cursor → everything with `updated_at`/seq strictly after it. Include tombstones for records deleted since the cursor (keep a `deletions` audit table or soft-delete with `deleted_at`).
- **Push** (`POST`): apply each upsert/delete under the caller's RBAC scope. Server owns `updated_at`. If the server's copy of an upserted id is newer than the client's cursor, that's a **conflict** → don't overwrite; return the server's copy in `conflicts`. Otherwise accept the write.
- Records the client receives (in `records` or `conflicts`) **overwrite local** — the server is authoritative on what it returns.
- **The client does not send a per-record version or `updated_at`.** Conflict resolution is entirely server-side (last-writer-wins by server receipt is fine to start).

---

## 4. Payload specifics you *do* need

Even treating payloads as opaque, lift these out for scoping/ordering:
- **`organization_id`** — present in the payload of every org-scoped record (`Team`, `FormInstance`, `ShareGrant`, `OrgMembership`, content). Use it as the RBAC tenant filter. (`Person`, `UserAccount`, and `Player` are reached via their org-scoped relations, not a direct `organization_id`.)
- **Ordering / cursor** — assign your own `updated_at`/seq on write; the payload has no timestamp to rely on.

**⚠️ Date encoding.** Any date *inside* a payload is a JSON **number = seconds since 2001-01-01 UTC** (Swift's `Date` default, not Unix epoch, not RFC3339). Examples: `RosterMembership.joinedOn/leftOn`, `FormInstance.submittedAt`, `ShareGrant.expiresAt`, `DevelopmentEntry.date`. Convert with `unix = value + 978307200`. If you'd rather standardize on RFC3339 strings, it's a one-line change to the client encoder — tell me and I'll switch it before you build serializers.

---

## 5. Example payloads (field names + types; key order is irrelevant)

```jsonc
// Organization
{ "id": "0A9A0000-0000-0000-0000-000000000001", "name": "My Coaching", "kind": "personal" }   // kind: personal|club

// Person  (all strings; empty string, never null)
{ "id":"<uuid>", "name":"Maya Chen", "guardian":"Alex Chen", "guardianPhone":"", "guardianEmail":"",
  "secondaryContactName":"", "secondaryContactPhone":"", "emergencyContactName":"", "emergencyContactPhone":"",
  "emergencyContactRelation":"", "allergies":"", "medicalNotes":"" }

// UserAccount  (personID/displayName omitted when nil)
{ "id":"<uuid>", "appleUserID":"<apple sub>", "personID":"<uuid>", "displayName":"Coach" }

// OrgMembership  (roles is a set → array, order not guaranteed; values ⊂ admin|director|coach|parent|player)
{ "id":"<uuid>", "personID":"<uuid>", "organizationID":"0A9A0000-…", "roles":["admin","director","coach"] }

// Team  (age_group e.g. "U12"; periodFormat "Halves"|"Quarters")
{ "id":"<uuid>", "name":"Northside Falcons", "ageGroup":"U12", "season":"Fall 2026", "accentName":"Teal",
  "periodFormat":"Halves", "defaultMinimumMinutes":30, "organizationID":"0A9A0000-…",
  "trainingDefaults": { "playerCount":8, "opponentCount":4, "coneCount":10, "zoneCount":1 } }

// RosterMembership  (nil optionals OMITTED; dates are seconds-since-2001)
{ "id":"<uuid>", "playerID":"<uuid>", "teamID":"<uuid>", "status":"active", "joinedOn": 773020800.0 }
//   status: active|guest|injured|inactive ; optional: jerseyNumber(int), position(str), leftOn(number)

// Player  (NOTE: no teamID — team is via RosterMembership; minMinutesOverride omitted when nil)
{ "id":"<uuid>", "personID":"<uuid>", "name":"Maya Chen", "number":2, "position":"DEF", "notes":"",
  "guardian":"Alex Chen", "guardianPhone":"", "guardianEmail":"", "secondaryContactName":"",
  "secondaryContactPhone":"", "emergencyContactName":"", "emergencyContactPhone":"",
  "emergencyContactRelation":"", "allergies":"", "medicalNotes":"", "developmentLog": [] }
//   position: GK|DEF|MID|FWD ; developmentLog: [{ "id":<uuid>, "date":<number>, "notes":"", "ratings":{"Passing":4} }]

// FormInstance  (submittedBy omitted when nil; submittedAt is seconds-since-2001)
{ "id":"<uuid>", "templateID":"F0000000-0000-0000-0000-000000000001", "templateVersion":1,
  "context":"pre_game", "subject": { "type":"athlete", "id":"<uuid>" },
  "contextRef": { "kind":"game", "id":"<uuid>" }, "submittedAt": 773107200.0, "note":"",
  "answers": [ { "fieldKey":"sleep", "number":4 }, { "fieldKey":"hasPain", "flag":false } ] }
//   context: tryout|pre_game|post_game|development|movement|coach_review
//   subject.type: athlete|coach|team ; contextRef.kind: game|session|event|tryout|standalone
//   each answer sets exactly one of: number (scale/count), flag (bool), text (str)

// ShareGrant  (grantedBy/expiresAt omitted when nil)
{ "id":"<uuid>", "shareableType":"drill", "shareableID":"<uuid>", "scope":"org", "organizationID":"0A9A0000-…" }
//   shareableType: session|drill|diagram|formTemplate ; scope: private|team|org|link

// Prefs  (singleton; envelope id is the literal "prefs")
{ "selectedTeamID":"<uuid>" }
```

`Session`, `Drill`, `Diagram`, `Game`, `Event`, `FormTemplate` are the same idea — store the payload as `jsonb`; model columns later only when you build features on them. (`FormTemplate` records are rare: the built-in templates live in the app binary and are **not** synced; only user/org custom templates appear.)

---

## 6. Minimal server to verify the localhost round-trip

The smallest thing that lets the client sync without erroring — an authenticated key/value store over records, no RBAC yet:

1. `POST /v1/auth/apple` → verify (or, for local dev, trust) the token, return `{ "token":"dev", "refreshToken":"dev-refresh", "personID":null }`.
2. `POST /v1/auth/refresh` → return `{ "accessToken":"dev", "refreshToken":"dev-refresh" }`. Stub it even for local dev: skip it and the first 401 from anywhere ends the session for good.
3. One table `records(account_id, type, id, payload jsonb, updated_at, deleted_at, seq bigserial)`, unique `(account_id, type, id)` — see the id-collision warning in §2.
4. `POST /v1/sync` → upsert each `upserts` row (bump `seq`), mark `deletes` with `deleted_at`, return `{ "cursor": "<max seq>", "conflicts": [] }`.
5. `GET /v1/sync?since=<seq>` → rows with `seq > since` (payloads for live, tombstones for `deleted_at`), return `{ records, deletes, "cursor":"<max seq>" }`.

`DELETE /v1/me` can wait until you are testing account deletion; until it exists that button fails cleanly and removes nothing.

Then set `BackendBaseURL` in the app's Info.plist to your host and sign in — you'll see a `GET /v1/sync` on launch, a `POST` carrying the whole local set right behind it (§7), and a `POST` per edit after that. Layer RBAC/entitlements on after the plumbing is proven.

---

## 7. First sync uploads everything

On the first sync for an account the client pushes its **entire local record set**, not just what changed after launch. It has to: `AppStore` seeds its diff baseline from local data, so without that bootstrap the first diff is empty by construction and a coach's existing season would never reach the server.

So on a fresh backend you will see a large `POST /v1/sync` immediately after the first pull, carrying the whole seeded roster. It runs after the pull, so anything the server already holds is merged in first and goes up in the same batch rather than being overwritten by a stale local copy.

The client marks the bootstrap done only on a server ack, and the flag is per account — so a bootstrap that fails is retried on the next launch, and a second coach signing in on the same device gets their own.

**Pushes are all-or-nothing from the client's side.** It advances its sync baseline only when a push is acknowledged in full; a batch that fails, partially or completely, stays in the next diff and is retried. You do not need to report per-record results — a non-2xx is enough.
