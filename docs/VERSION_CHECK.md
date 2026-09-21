# Version Check — Ops Guide

How to keep the **mandatory / optional update gate** working on iOS after each App Store release.

The app already checks on cold launch, foreground, and login. It will not block the dashboard correctly unless **Firebase Remote Config** is updated after a release is live on the App Store.

---

## How it works (iOS)

| Source | Role |
|--------|------|
| **Apple iTunes Lookup** (`id=6791077796`) | Latest **publicly installable** version |
| Firebase `ios_minimum_supported_version` | Mandatory floor — installed below this → **Update Required** (non-dismissable) |
| Firebase `ios_force_update` | Emergency switch — when `true`, anyone behind the App Store version must update |

**Rules (simplified):**

1. Installed &lt; reachable Firebase floor → **required**
2. `ios_force_update == true` and installed &lt; App Store version → **required**
3. Otherwise installed &lt; App Store version → **optional** (user can dismiss)
4. Installed ≥ App Store (or TestFlight ahead of Store) → up to date
5. Apple lookup fails → still honor a valid Firebase floor; do **not** invent a mandatory target Apple does not list yet

Mac Catalyst uses separate `mac_*` Remote Config keys and does **not** use the iOS App Store lookup. Leave `mac_*` unset unless you intentionally ship Mac updates.

---

## Prerequisites

1. Firebase project wired with `GoogleService-Info.plist` in the app bundle (`FirebaseBootstrap.hasConfigFile`).
2. Firebase Console → **Remote Config** enabled for the same project.
3. App Store listing live: Apple ID `6791077796` · bundle `com.surainvestments.roster`.

---

## Remote Config keys (iOS)

Create / maintain these parameters in Firebase Console → Remote Config:

| Key | Type | Default in app | Purpose |
|-----|------|----------------|---------|
| `ios_minimum_supported_version` | String | `0.0.0` | Hard floor. Example: `2.1` |
| `ios_force_update` | Boolean | `false` | Kill switch: force everyone below the current App Store version |
| `ios_latest_version` | String | installed version | Legacy / unused on iOS hybrid path (Apple Lookup is authoritative). Safe to leave set for reference. |

Use marketing-version numbers (`major.minor` or `major.minor.patch`), e.g. `2.1` — not build numbers.

---

## Checklist after every App Store release

Do this **only after** the new version is visible on Apple’s lookup API (propagation can lag App Store Connect “Ready for Sale”).

### 1. Confirm Apple sees the new version

Open (replace version expectation with yours):

```text
https://itunes.apple.com/lookup?id=6791077796&country=au
```

In the JSON, check `results[0].version` matches the marketing version you just shipped (same as `MARKETING_VERSION` in `project.yml`).

If the lookup still shows the **old** version, **do not** raise the Firebase floor yet — users could be locked out with nothing to install.

### 2. Decide policy

| Goal | Action in Remote Config |
|------|-------------------------|
| Soft nudge only | Leave `ios_minimum_supported_version` unchanged; leave `ios_force_update` = `false`. Optional sheet appears when behind Store. |
| Block old builds (normal mandatory) | Set `ios_minimum_supported_version` to the **new** version (or the oldest build you still allow). Publish. |
| Emergency (pull everyone off a bad build) | Set `ios_force_update` = `true` (and ensure Store already shows a good version). Publish. |

### 3. Publish Remote Config

In Firebase Console → Remote Config → **Publish changes**.

The app fetches on cold launch, foreground and login, and keeps a real-time
Remote Config listener while it is open. Existing clients pick up the new
values on their next successful online check.

### 4. Smoke-test on a device

1. Install an **older** build (or temporarily set floor above the installed version).
2. Cold launch → full-screen **Update Required** (non-dismissable).
3. Confirm **Update Now** opens `https://apps.apple.com/app/id6791077796`.
4. Log in on a current build → no gate; dashboard loads.
5. Optional: set floor back / disable force → publish → relaunch older build policy as intended.

---

## Rollback (no app release required)

If a mistaken floor / force flag locks users out:

1. Firebase Remote Config → lower `ios_minimum_supported_version` (e.g. back to `0.0.0` or the previous floor).
2. Set `ios_force_update` = `false`.
3. **Publish**.
4. Users clear the gate on the next launch / foreground / login check.

---

## In-app release registry (separate)

The static changelog in `Rosterra/Models/AppRelease.swift` (`ReleaseHistory`) is **not** the update gate. When cutting a release still:

1. Prepend an entry to `ReleaseHistory.all`.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Ship to App Store.
4. Then follow the Remote Config checklist above.

---

## Code map

| File | Role |
|------|------|
| `Rosterra/Services/AppVersionCheckService.swift` | Apple Lookup + Firebase Remote Config + pure `AppVersionCheck.evaluate` |
| `Rosterra/ViewModels/AppVersionCheckViewModel.swift` | Status for UI; serialized overlapping checks |
| `Rosterra/App/RootView.swift` | Triggers on `.active` and `auth.uid`; presents gate |
| `Rosterra/Features/Shared/UpdateRequiredView.swift` | Non-dismissable mandatory UI |
| `Rosterra/Features/Shared/UpdateAvailableSheet.swift` | Dismissable optional UI |
| `Rosterra/Services/AppConfig.swift` | `appStoreURL` / `appStoreName` |
| `RosterraTests/AppVersionCheckServiceTests.swift` | Policy + view-model tests |

---

## Gotchas

- **Never raise the floor before Apple lookup shows the new version.**
- Always query the Australian storefront (`country=au`); the API defaults to
  the US storefront, where Rosterra is not listed.
- Floor ahead of Store is intentionally **not** enforced as mandatory (avoids an unrecoverable loop).
- Unparseable installed version fails open (does not block).
- Staff and managers are both gated on iOS before any dashboard.
- Mac is isolated via `mac_*` keys; iOS Store lookup does not apply there.
