# Native Android Staff App — Planning Pack

> **Status:** Phase 1 audit complete · Phase 2 roadmap ready · **No Android implementation yet**  
> **Source of truth for behaviour:** Native iOS app (`Rosterra/`)  
> **Manager scope:** Explicitly out of scope until Staff reaches production quality  
> **Last updated:** 2026-07-22

This pack answers the Native Android Staff App planning brief. Read in order:

| # | Document | Purpose |
|---|----------|---------|
| 1 | [`01-ios-staff-audit.md`](01-ios-staff-audit.md) | Complete iOS Staff discovery audit (screens, flows, APIs, UX) |
| 2 | [`02-staff-app-structure.md`](02-staff-app-structure.md) | Staff tabs / destinations for Android parity |
| 3 | [`03-staff-permissions.md`](03-staff-permissions.md) | Allow / deny matrix (client + Firestore + Storage + Worker) |
| 4 | [`04-notifications.md`](04-notifications.md) | Push, local reminders, deep links, badges |
| 5 | [`05-cache-offline-security.md`](05-cache-offline-security.md) | Offline-first cache, performance, security review |
| 6 | [`06-implementation-roadmap.md`](06-implementation-roadmap.md) | Phase-by-phase Android build plan |

## Hard constraints (carry into Android)

1. **Staff-only product surface** until Staff is production-ready. Do not ship Manager UI, routes, or all-staff listeners.
2. **Parity with iOS Staff behaviour**, using Material Design 3 patterns where Android-native UX is clearer.
3. **Same backend:** Firebase Auth / Firestore / Storage / Messaging / Crashlytics + Cloudflare Worker at `https://sura-roster.com`.
4. **Same calendar model:** `Australia/Adelaide`, Monday-start weeks (`RosterCalendar` semantics).
5. **Never weaken security:** respect deployed Firestore/Storage rules; never add client-only “manager mode” shortcuts.
6. **No development starts** until this pack is accepted as the baseline (Phase 1 complete).

## Related iOS docs (supporting, may be partially stale)

- `docs/staff-guide.md` — staff feature overview (verify against code where noted in audit gaps)
- `docs/architecture.md` — listeners / layering
- `docs/tasks-feature.md`, `docs/shift-attendance.md`
- `docs/reference/firestore.rules.deployed`, `docs/reference/storage.rules`
- `docs/APP_STORE_SUBMISSION.md` — privacy / permissions (iOS); Android Play Data Safety is a later milestone

## Recommended Android stack (decision baseline for Phase 2)

| Concern | Recommendation |
|---------|----------------|
| Language | Kotlin |
| UI | Jetpack Compose + Material 3 |
| Architecture | Single-activity · UI → ViewModel → Repository → Firebase/Worker |
| DI | Hilt |
| Async | Coroutines + Flow |
| Navigation | Navigation Compose |
| Local DB / cache | Room (structured) + Firestore persistent cache + DataStore |
| Images | Coil |
| Push | FCM |
| Crash | Firebase Crashlytics |
| Tests | JUnit + Truth + Compose UI tests; port `BusinessRules` first |

Final stack choices are confirmed in roadmap Phase A0 before feature work.
