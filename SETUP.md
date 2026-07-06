# Setup & Signing

SoccerCoachKit uses several entitled capabilities. This documents how they're
provisioned and how to build the app signed for a device.

## Capabilities

| Capability | Used by | Entitlement |
|---|---|---|
| **App Group** | Home Screen / Lock Screen widget + Live Activity data sharing | `com.apple.security.application-groups` → `group.com.monsoudzanaty.SoccerCoachKit` (app **and** widget) |
| **Sign in with Apple** | The login gate | `com.apple.developer.applesignin` (app) |
| **iCloud (key-value)** | Cross-device data sync | `com.apple.developer.ubiquity-kvstore-identifier` (app) |
| **Live Activities** | Game Day live score/clock | Info.plist `NSSupportsLiveActivities` (no portal capability) |

Entitlements live in `SoccerCoachKit/SoccerCoachKit.entitlements` and
`GameWidget/GameWidget.entitlements`, wired up in `project.yml`. The App Group id
must stay identical in both files for cross-process sharing to work.

## Signing

- **Team:** `CNK57345QT` (`DEVELOPMENT_TEAM` in `project.yml`).
- **Style:** Automatic (`CODE_SIGN_STYLE: Automatic`) — Xcode manages the App IDs
  and provisioning profiles.

The capabilities are already provisioned: a signed device build succeeds and the
profiles include the App Group, Sign in with Apple, and iCloud KVS entitlements.

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
