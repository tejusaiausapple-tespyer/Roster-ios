# Phase 2 — Android Staff Implementation Roadmap

> **Do not start feature coding until Phase 1 pack is accepted.**  
> Manager development is forbidden until Staff is production-ready (after Phase S0).  
> Target: feature parity with iOS Staff shell + Material 3 polish.

---

## Phase index

| Phase | Name | Outcome |
|-------|------|---------|
| **A0** | Foundations & decisions | Repo, stack, CI, design tokens, empty Staff shell |
| **A1** | Auth & session gates | Login → password → profile → biometrics → Staff hub |
| **A2** | Data layer & Staff listeners | Room + Firestore staff-scoped sync |
| **A3** | Home + Clock + Notifications sheet | Daily dashboard parity |
| **A4** | Roster + Timesheets + History | Core shift workflow |
| **A5** | Availability | Worker-backed editor |
| **A6** | Tasks + Daily Jobs + photos | Completion parity |
| **A7** | Account + Payslips + legal + deletion | Settings parity |
| **A8** | Push, locals, deep links | Full notification system |
| **A9** | Offline, perf, a11y polish | Production hardening |
| **S0** | Staff production gate | Store-ready Staff-only release |
| **M0+** | Manager planning | **Only after S0** |

Each phase below lists: features, dependencies, backend endpoints, Firestore, security, offline/cache, tests, completion criteria.

---

## A0 — Foundations & decisions

### Features
- Confirm Kotlin + Compose + Material 3 + Hilt + Navigation + Coroutines/Flow + Room + Coil + FCM + Crashlytics  
- App module structure (`app`, `core`, `data`, `domain`, `feature-*`)  
- Design system: color/type/spacing tokens mapped from iOS Theme (not glass copy)  
- Empty `StaffNav` with 5 tabs stubs  
- Adelaide Monday-week calendar utilities port (`RosterCalendar` / `BusinessRules` pure Kotlin)  
- CI: unit tests + lint; debug signing  

### Dependencies
- Firebase Android BoM; Play services  
- Access to same Firebase project as iOS (`roster-8a270` / production config)  

### Backend / Firestore
- None yet (bootstrap only)

### Security
- ApplicationId / package distinct from iOS bundle; correct `google-services.json`  
- No manager feature modules included in Staff product flavor if using flavors  

### Offline / cache
- Enable Firestore persistent cache  
- Room DB skeleton  

### Testing checklist
- [ ] Calendar week-start + TZ unit tests (port iOS tests)  
- [ ] BusinessRules port: submit/absence/displayStatus/needsAction/password  

### Completion criteria
- App launches to stub shell; CI green; design tokens documented; **Phase 1 docs linked in README**

---

## A1 — Auth & session gates

### Features
- Email/password login, remember me, forgot password  
- Forced password change + Worker complete  
- Profile completion (DOB/address/phone)  
- Biometric quick login + device unlock gate + background relock  
- Locked/inactive account handling  
- Sign out clears listeners/tokens/reminders  

### Dependencies
- A0 calendar/rules; Firebase Auth  

### Backend endpoints
- Firebase Auth email/password + reset  
- `POST /api/complete-password-change`  

### Firestore
- Read/write own `users/{uid}` allow-listed fields; `lastLoginAt`  

### Security
- Store credentials in Keystore-backed EncryptedSharedPreferences / BiometricPrompt  
- Never log passwords  

### Offline / cache
- Session restore offline → unlock gate works; network needed for fresh login  

### Testing checklist
- [ ] Gate order truth table (port `AppRoute` tests)  
- [ ] Biometric freshness >7 days refuses quick login  
- [ ] Forced password path calls Worker  

### Completion criteria
- Staff test user can reach empty Staff tabs through all gates on device/emulator  

---

## A2 — Data layer & Staff listeners

### Features
- `StaffRepository` with staff-scoped listeners matching iOS `RosterRepository` staff branch  
- Room mirroring + Flow to UI  
- `refreshFromServer()`  
- Connectivity observer  

### Dependencies
- A1 authenticated uid + role check (reject manager accounts for this app)  

### Backend endpoints
- None required beyond Firestore/Auth  

### Firestore collections
- `users/{uid}`, `shifts`, `timesheets`, `messages`, `tasks`, `task_completions`, `shift_attendance`, `daily_job_assignments`, `settings/app|locations|availabilityLocks`  

### Security
- Queries always constrained; instrumented permission-denied tests for forbidden collections  

### Offline / cache
- Listeners populate Room; UI reads Room first  

### Testing checklist
- [ ] Fake Firestore / emulator tests for query filters  
- [ ] Manager uid cannot use Staff app (blocked)  

### Completion criteria
- Home stub can display cached shift count from live listener  

---

## A3 — Home + Clock + Notifications sheet

### Features
- Home dashboard parity (greeting, today, hours tiles, upcoming, bell badge)  
- ClockInCard full state machine + geofence dialogs  
- Notifications sheet: messages + daily jobs  
- Add to Calendar / ICS fallback  

### Dependencies
- A2 data; Location permission UX; Calendar intent  

### Backend endpoints
- `POST /api/send-notification` for `shift-started` / `shift-ended` (fire-and-forget)  

### Firestore
- Read shifts/timesheets/messages/jobs/settings; write attendance; mark messages read; toggle daily jobs  

### Security
- Location only when-in-use; no background tracking service  

### Offline / cache
- Clock session DataStore; attendance sync queue; UI from Room  

### Testing checklist
- [ ] Clock session survives process death  
- [ ] Geofence enforced vs warn paths from location settings  
- [ ] Badge counts unread + pending jobs  

### Completion criteria
- Staff can clock a shift on device with GPS and see Home parity  

---

## A4 — Roster + Timesheets + History

### Features
- Week selector + day sections + ShiftCard actions  
- SubmitHours / ReportAbsence / Undo  
- History filters + resubmit  
- Deep-link pending submit/absent hosts  

### Dependencies
- A3 clock session prefill; BusinessRules  

### Backend endpoints
- `POST /api/send-notification` (`timesheet-submitted`, `timesheet-absent`)  

### Firestore
- Timesheet create/update/delete (absence undo) within rules  

### Security
- No approval fields; client validation mirrors rules  

### Offline / cache
- View offline; writes online-only with clear errors (outbox optional later)  

### Testing checklist
- [ ] canSubmit / canReportAbsence matrix  
- [ ] Resubmit clears rejection  
- [ ] Deep link opens sheet after History push  

### Completion criteria
- Full timesheet happy path + rejection resubmit verified on device  

---

## A5 — Availability

### Features
- Week editor −2…+12; day sheet; recurring; reset; locked banners; Save  

### Dependencies
- A2 user + locks listeners  

### Backend endpoints
- `POST /api/staff/availability` (**required**)  

### Firestore
- Read user + locks; **no direct weeklyAvailability write**  

### Security
- Payload `userId` must equal auth uid; Worker enforces locks  

### Offline / cache
- Read offline; save requires network; optimistic merge after success  

### Testing checklist
- [ ] Locked week cannot save  
- [ ] Worker error surfaces toast  

### Completion criteria
- Manager web/iOS sees staff availability update after Android save  

---

## A6 — Tasks + Daily Jobs + photos

### Features
- Tasks tab parity; detail; camera capture; ≤4 photos; complete; redo UI  
- Daily jobs in notifications (already started in A3) finalize  

### Dependencies
- A2; Camera permission; Storage rules; Image compressor  

### Backend endpoints
- `POST /api/send-notification` (`task-completed`, `jobs-all-completed`)  

### Firestore / Storage
- Write `task_completions`; upload `task_photos/{uid}/…`  

### Security
- Storage path uid match; no gallery as primary on production builds  

### Offline / cache
- List offline; hold local bitmaps until upload; Coil for ref photos  

### Testing checklist
- [ ] Photo limit + compression  
- [ ] Completion id `{taskId}_{date}`  
- [ ] Local-only proof display after submit  

### Completion criteria
- Manager can review Android-submitted task completion + photos  

---

## A7 — Account + Payslips + legal + deletion

### Features
- Account sections parity: photo local, email/password, biometric toggle, appearance, notifications settings entry, payslips, privacy/terms, contact, deletion request, sign out  

### Dependencies
- A1 auth; A2 payslip fetch  

### Backend endpoints
- `POST /api/account-deletion/request` `{ "via": "android" }`  
- Firebase email verification / password update  

### Firestore
- Profile allow-list; payslips month queries; token cleanup on logout  

### Security
- Deletion lifecycle fields Worker-only; verify email-change against **live** rules  

### Offline / cache
- Payslip month markers; legal offline  

### Testing checklist
- [ ] Payslip cache-first months  
- [ ] Deletion request status UI  
- [ ] Sign out clears sensitive local state  

### Completion criteria
- Account flows match iOS staff smoke paths  

---

## A8 — Push, local reminders, deep links

### Features
- FCM registration + token docs (`platform: android-native`)  
- Channels; event routing; local ShiftReminderScheduler port  
- App Links / deep links; boot reschedule  

### Dependencies
- A3–A7 destinations exist  

### Backend endpoints
- Token Firestore writes; receive Worker pushes  

### Firestore
- `notificationTokens` CRUD  

### Security
- Ignore manager-only events; whitelist deep links  

### Offline / cache
- Locals fire offline if scheduled  

### Testing checklist
- See `04-notifications.md` testing list  

### Completion criteria
- Every staff event in audit routes correctly on a physical device  

---

## A9 — Offline, performance, a11y polish

### Features
- Offline banner; retry UX; skeleton parity; haptics; Reduce Motion; TalkBack labels; large font; image sweep; Crashlytics non-fatal for sync failures; Play Data Safety draft  

### Dependencies
- Feature complete A1–A8  

### Backend / Firestore
- None new  

### Security
- Final pass of `03` + `05` checklists  

### Offline / cache
- Attendance outbox reliability; no destructive cache bugs  

### Testing checklist
- [ ] Airplane mode walkthrough  
- [ ] TalkBack critical paths  
- [ ] Battery: no runaway location  

### Completion criteria
- Performance/a11y sign-off checklist green  

---

## S0 — Staff production gate

### Features
- Store listing assets; versioning; ProGuard; privacy policy URL; smoke test Android port of `docs/smoke-test.md` staff steps  
- **No Manager code paths shipped**  

### Completion criteria
- [ ] Staff smoke test on physical device signed off by Sura  
- [ ] Unit/UI tests green in CI  
- [ ] Security deny-list tests green  
- [ ] Crash-free critical paths  
- [ ] Play policy / Data safety filled  
- [ ] Feature parity matrix vs `01-ios-staff-audit.md` checked  

**Only after S0:** begin Manager planning (M0+), separate app module/flavor or later phase — not before.

---

## Cross-phase parity matrix (track in PR descriptions)

| iOS Staff capability | Phase | Done? |
|----------------------|-------|-------|
| Auth gates | A1 | |
| Home + hours | A3 | |
| Clock + geofence | A3 | |
| Notifications sheet | A3 | |
| Roster + submit/absence | A4 | |
| History | A4 | |
| Availability | A5 | |
| Tasks + photos | A6 | |
| Daily jobs | A3/A6 | |
| Payslips | A7 | |
| Account security/legal/deletion | A7 | |
| FCM + local reminders | A8 | |
| Offline polish | A9 | |

---

## Explicit non-goals until S0

- Manager UI / all-staff listeners  
- Multi-tenant SaaS plumbing  
- In-app purchases / ads / analytics SDKs beyond Crashlytics  
- Cloud profile photo upload (unless product decision)  
- Passkeys as primary auth  
- Weakening Firestore rules for client convenience  

---

## Suggested first engineering PR after approval

1. Create/confirm Android repo or module  
2. Land A0 (skeleton + ported `BusinessRules`/`RosterCalendar` tests)  
3. Link this pack from Android README  

This iOS-repo documentation PR **does not** contain Android application code — by design.
