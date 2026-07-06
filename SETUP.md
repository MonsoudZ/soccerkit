# Setup & Signing

SoccerCoachKit uses several entitled capabilities. This documents how they're
provisioned and how to build the app signed for a device.

## Capabilities

| Capability | Used by | Entitlement |
|---|---|---|
| **App Group** | Home Screen / Lock Screen widget + Live Activity data sharing | `com.apple.security.application-groups` → `group.com.monsoudzanaty.SoccerCoachKit` (app **and** widget) |
| **Sign in with Apple** | The login gate | `com.apple.developer.applesignin` (app) |
| **iCloud (CloudKit)** | Cross-device, record-level data sync | `com.apple.developer.icloud-services` → `CloudKit` + `com.apple.developer.icloud-container-identifiers` → `iCloud.com.monsoudzanaty.SoccerCoachKit` (app) |
| **Push Notifications** | CloudKit sync + remote Live Activity updates | `aps-environment: development` (app) |
| **Live Activities** | Game Day live score/clock | Info.plist `NSSupportsLiveActivities` (no portal capability) |

Entitlements live in `SoccerCoachKit/SoccerCoachKit.entitlements` and
`GameWidget/GameWidget.entitlements`, wired up in `project.yml`. The App Group id
must stay identical in both files for cross-process sharing to work.

## Signing

- **Team:** `CNK57345QT` (`DEVELOPMENT_TEAM` in `project.yml`).
- **Style:** Automatic (`CODE_SIGN_STYLE: Automatic`) — Xcode manages the App IDs
  and provisioning profiles.

The capabilities are already provisioned: a signed device build succeeds and the
profiles include the App Group, Sign in with Apple, and iCloud CloudKit
entitlements.

### CloudKit sync

Cross-device sync uses **CloudKit** (`CKSyncEngine`, iOS 17+) rather than a
whole-document blob, so two devices editing different records merge instead of
clobbering each other. Each entity (team, player, drill, session, diagram, game,
event) is its own record in a per-coach private-database zone; app preferences
are a single `Prefs` record. Same-record conflicts resolve **server-wins**.

- The pure record mapping/diff (`SyncRecords`) is unit-tested (`SyncRecordsTests`).
- The `CKSyncEngine` wiring (`CloudKitSyncService`) **must be validated
  on-device** — it needs a signed build, an iCloud-signed-in account, and the
  provisioned CloudKit container. It cannot run in the unsigned Simulator.
- First device run creates the container schema in the CloudKit **Development**
  environment automatically; promote to Production in the CloudKit Dashboard
  before shipping.
- Sync is user-toggleable in Settings → Sync and is keyed per Apple ID (each
  coach gets an isolated zone), matching the local per-user persistence
  namespace.

### Build signed (device)

```sh
xcodegen generate                     # regenerate the project after any project.yml change
xcodebuild -project SoccerCoachKit.xcodeproj -scheme SoccerCoachKit \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

`-allowProvisioningUpdates` lets Xcode register/refresh App IDs and profiles as
needed. Or just open `SoccerCoachKit.xcodeproj` in Xcode, confirm the team on
both targets (SoccerCoachKit, GameWidget), and Run to a connected device.

### Simulator / CI (unsigned)

Local capability entitlements aren't enforced in the Simulator, and CI builds
unsigned:

```sh
xcodebuild test -project SoccerCoachKit.xcodeproj -scheme SoccerCoachKit \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Note: App Group sharing and Sign in with Apple only work end-to-end on a
**signed** build (device or signed simulator run from Xcode), not an unsigned
CLI build.

## Optional: remote Live Activity updates (Push)

The Game Day Live Activity works with local updates out of the box. To also push
`content-state` updates from a server (the token path in
`GameActivityController`), add the Push Notifications capability:

1. In `project.yml`, add to the app target's `entitlements.properties`:
   `aps-environment: development`
2. `xcodegen generate` and build with `-allowProvisioningUpdates` (Xcode enables
   Push on the App ID). You'll also need an APNs-capable backend to send the
   pushes.
