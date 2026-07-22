# Phase 1 — Native iOS Staff App Audit

> Complete discovery of Staff-side behaviour in the Rosterra iOS app.  
> Manager features are listed only as **forbidden** surfaces.  
> Code paths cited under `/workspace/Rosterra/`.

---

## 1. Product identity (Staff)

Rosterra Staff is invite-only workforce software: view published shifts, clock in/out with GPS, submit/resubmit timesheets, report absence, manage availability, complete tasks/daily jobs with photo proof, read messages, view payslips, manage account security.

**Roles:** after login, `AppUser.role` routes to Staff shell (`MainTabView`) or Manager shell. Android Staff app must only implement the Staff shell.

**Tenancy:** intentionally single-tenant (one Firebase project / business). No `businessId` partition.

---

## 2. Navigation — bottom tabs

Source: `Features/Shell/MainTabView.swift`

| Order | Tab | View | Icon (SF Symbol) | Android Material 3 analogue |
|------:|-----|------|------------------|-----------------------------|
| 1 | Home | `HomeView` | `house` | Home |
| 2 | Roster | `RosterView` | `calendar` | Roster |
| 3 | Tasks | `TasksView` | `list.bullet.clipboard` | Tasks |
| 4 | Availability | `AvailabilityView` | `calendar.badge.clock` | Availability |
| 5 | Account | `AccountView` | `person.crop.circle` | Account |

**Not separate tabs on iOS (do not invent unless roadmap explicitly decides otherwise):**

| Destination | How reached |
|-------------|-------------|
| Notifications / Daily Jobs | Home → bell → `NotificationsSheet` |
| Shift History | Roster → “View Shift History” → `HistoryView` |
| Payslips | Account → Payslips → `PayslipsView` |
| Privacy / Terms | Account → About |
| Submit Hours / Report Absence | Sheets from Roster (also deep-linked) |

Tab change haptic: `Haptics.tabChange()`.

---

## 3. Authentication & gate flow

Sources: `App/RootView.swift`, `App/AppRoute.swift`, `ViewModels/AuthViewModel.swift`

```
Launch
  → missing GoogleService-Info.plist → SetupRequiredView (dev only)
  → restoring session → SplashView
  → unauthenticated → LoginView
  → authenticated + profile loading → SplashView
  → mustChangePassword → ChangePasswordView(forced)  [both roles]
  → needsProfileCompletion → ProfileCompletionView   [staff model]
  → deviceAuth enabled & not verified → DeviceAuthGateView
  → staff → MainTabView
```

### Login (`Features/Auth/LoginView.swift`)

- Email + password; show/hide password; Remember me
- Forgot password sheet → Firebase reset email
- Quick login: Face ID / Touch ID / device passcode via `BiometricCredentialStore` (refused if last manual login > 7 days)
- Passkey path exists (`PasskeyStore`) but is not primary
- Rejects locked/inactive accounts (sign out + error)
- On success: start repository listeners; request notification permission + FCM register
- Animations: error shake (respect Reduce Motion); success/error haptics

### Forced password change (`ChangePasswordView`)

- Current / new / confirm; password rules checklist (`BusinessRules.passwordErrors`)
- Calls Firebase password update + Worker `/api/complete-password-change`
- Updates biometric/passkey stored credentials if present
- Forced mode: Sign out available

### Profile completion (`ProfileCompletionView`)

- Required: DOB, address (MapKit autocomplete), phone
- Writes `dob`, `address`, `phone`, `profileUpdateRequired: false` via `RosterRepository.updateProfile`
- Sign out available

### Device auth gate (`DeviceAuthGateView`)

- Local unlock only (offline-capable)
- Auto-prompt on appear; Unlock button; Sign out
- Relock after background beyond `AppConfig.deviceAuthBackgroundRelock`
- Fresh manual login skips gate for that session (`deviceAuthVerified = true`)

### Email change (`ChangeEmailView`) — Account sheet

- Reauth with password; send verification; attempt Firestore `email` / `emailChangeRequired` sync  
- **Audit gap:** deployed rules snapshot allow-list may deny those Firestore fields — verify live rules before Android ports this write

---

## 4. Screen inventory

### 4.1 Home — `Features/Home/HomeView.swift`

**Purpose:** Staff dashboard.

**UI**
- Company title pill (`settings/app.companyName`)
- Greeting (first name)
- Bell with badge = unread messages + pending daily jobs
- Today: `ShiftCard`(s) or empty “No shift today”
- `ClockInCard` when current shift is clockable
- Approved hours tiles: week / month / year / all-time (`HoursMetrics`)
- Upcoming shifts + “View roster”
- Context menu: Add to Calendar

**Actions**
- Bell → `NotificationsSheet`
- Submit/absence actions → set `AppRouter` pending IDs + switch to Roster
- Pull to refresh → `repo.refreshFromServer()`
- Add to Calendar → `CalendarService` (or `.ics` share fallback)

**States:** loading skeletons; empty today; calendar error toast.

**Permissions:** calendar write; location primed at staff session start (for clock).

### 4.2 Clock in/out — `Features/Home/ClockInCard.swift`

**Purpose:** Device-local clock session + verified attendance sync.

**States:** Starts soon (locked) → Start Shift → On the clock (live timer) → Start/End Break → End Shift → Submit hours.

**Behaviour**
- GPS one-shot via `LocationService` on start/end; geofence confirm/block from `settings/locations`
- Early leave note alert; finish choice stayed-back vs rostered end
- Persist `ClockSession` in `UserDefaults["clockSession.<uid>"]` (survives relaunch)
- Firestore: `shift_attendance/{shiftId}` create/update with server timestamps
- If attendance write fails: local session continues; alert that verified sync failed
- Clears forgot-start / forgot-end local reminders appropriately
- Fire-and-forget Worker notify: `shift-started` / `shift-ended`

### 4.3 Notifications sheet — `Features/Home/NotificationsSheet.swift`

**Purpose:** Inbox + Daily Jobs panel (not a tab).

**UI**
- Active messages list; empty “No notifications”
- Daily Jobs with Complete/Undo + progress badge
- Done dismiss

**Writes:** `markMessageRead` / `markMessagesRead` (`read: true`); `setDailyJobCompleted`.

### 4.4 Roster — `Features/Roster/RosterView.swift`

**Purpose:** Week-by-week published shifts + timesheet actions.

**UI**
- Week stats: Shifts, Hours, To do
- `WeekSelector` (Monday weeks)
- “View Shift History” → `HistoryView`
- Action-needed horizontal chips
- Day sections + `ShiftCard` / “No shift”
- Swipe + context menu: Submit/Edit/Resubmit, Absent, Undo absence, Calendar

**Sheets:** `SubmitHoursSheet`, `ReportAbsenceSheet`, `ShareSheet`  
**Deep links:** `.task` on `pendingSubmitShiftId` / `pendingAbsentShiftId` must stay on `NavigationStack` (not root-only) — iOS gotcha documented in `agents.md`.

**Business rules:** `staffShiftDateRange` (28 back / 56 forward); `canSubmitHours` / `canReportAbsence` / `displayStatus` / `needsStaffAction`.

### 4.5 Submit hours — `Features/Shared/SubmitHoursSheet.swift`

- Prefill rostered times or clock session (rounded 5m, break 0–90)
- Notes optional; validate hours > 0
- Pending incomplete tasks → confirm “Submit Anyway”
- Write `timesheets/{shiftId}` pending; clear clock session on success
- Worker: `timesheet-submitted`
- Modes: Submit / Update (pending/draft) / Resubmit (rejected)

### 4.6 Report absence — `Features/Shared/ReportAbsenceSheet.swift`

- Optional reason → `absent_reported` timesheet
- Undo via delete of own `absent_reported` doc
- Worker: `timesheet-absent`
- **Doc vs code gap:** some docs say absence before submittable; code + rules require `isSubmittableStaffShift` — **Android must follow code/rules**

### 4.7 History — `Features/History/HistoryView.swift`

- Pushed from Roster (not a tab)
- Summary tiles; pending banner; search; period/status filters; month sections
- Rejected swipe → Resubmit (routes pending submit to Roster)

### 4.8 Tasks — `Features/Tasks/TasksView.swift`

- Week/day selector; stats Tasks / Completed / Pending
- Cards: priority, due time, redo, description, completed time
- Detail sheet: reference photo (`AsyncImage`), camera proof (max 4), note, Complete
- Upload Storage `task_photos/{uid}/...`; write `task_completions/{taskId}_{date}`
- Local cache `Documents/task_photos/`; staff UI local-only after submit
- Frequencies: once / daily / weekly; UI filters assigned + active for day

### 4.9 Availability — `Features/Availability/AvailabilityView.swift` + `DayEditSheet`

- Weeks −2…+12; locked banners (manager lock + past/current rules)
- Day rows; Set as recurring; Reset; toolbar Save
- Save via Worker `/api/staff/availability` then optimistic local `currentUser.weeklyAvailability`
- No offline queue

### 4.10 Account — `Features/Account/AccountView.swift`

**Sections:** Profile photo (local `profile_photo.jpg`) · Email verification / change · Details · Stats · Payslips · Notifications · Appearance (dark mode `@AppStorage`) · Security (biometric unlock, change password) · About (Privacy, Terms, Contact mailto) · Delete account · Sign out

### 4.11 Payslips — `Features/Account/PayslipsView.swift`

- Month picker; list gross/net/status; PDF sheet (`PayslipPDFSheet`, staff mode)
- Cache-first month fetch; `payslipMonthsDownloaded.<uid>` markers
- Only `status in [submitted, archived]` for own `staffId`

### 4.12 Legal — `PrivacyPolicyView`, `TermsOfServiceView`

Static offline content. Version history view exists but staff Account currently shows plain version row (manager links changelog).

---

## 5. Permissions (iOS → Android mapping)

| Capability | iOS | When | Android equivalent |
|------------|-----|------|-------------------|
| Notifications | alert/badge/sound | Login + Account explainer | POST_NOTIFICATIONS + FCM |
| Location when-in-use | clock start/end | Staff session prime + clock | ACCESS_FINE_LOCATION (foreground) |
| Camera | task proof | Tasks | CAMERA |
| Photo library | profile photo; camera fallback | Account / simulator | READ_MEDIA_IMAGES (scoped) |
| Calendar write | Add to Calendar | Home/Roster | WRITE_CALENDAR or intent insert |
| Biometrics | Face ID / fingerprint / PIN | Login + gate + Account | BiometricPrompt + Keystore |
| Internet | all sync | Always | INTERNET |

No microphone, contacts address book, continuous background location, advertising ID.

---

## 6. Local storage inventory

| Key / path | Purpose |
|------------|---------|
| Firestore persistent cache (unlimited) | Offline listener data |
| `UserDefaults clockSession.<uid>` | Local clock session |
| `UserDefaults preferredColorScheme` | Appearance |
| `UserDefaults roster_last_manual_login_date` | Biometric login freshness |
| `UserDefaults roster_last_fcm_token` | Logout token delete |
| `UserDefaults payslipMonthsDownloaded.<uid>` | Payslip offline months |
| Keychain device auth flag `roster_device_auth_<uid>` | Unlock gate |
| Keychain biometric password | Quick login |
| `Documents/profile_photo.jpg` | Profile avatar (local-only today) |
| `Documents/task_photos/` | Proof photo cache |
| Temp `.ics` / PDF | Share fallbacks |

---

## 7. Animations, haptics, gestures

- Tab change haptic
- Selection / success / error / warning / light haptics across forms and clock
- Login error shake (Reduce Motion aware)
- Roster spring scroll-to-day
- Swipe actions on shift/history rows
- Context menus (calendar, remove photo)
- Sheet detent sizing (medium/large)
- Clock live `TimelineView` timer
- Payslip month picker spring expand
- Skeleton loading cards/rows across lists

Android should map haptics to `HapticFeedbackConstants` / `Vibrator` and motion to Material motion; respect system Reduce Motion / animation scales.

---

## 8. Loading / empty / error patterns

| Pattern | Where |
|---------|--------|
| Skeleton cards/rows | Home, Roster, History, Payslips |
| Empty copy | “No shift today”, “No Tasks Scheduled”, “No notifications”, “Nothing here yet”, “No payslips for {month}” |
| Banner | Auth errors, validation, pending approval |
| Toast | Calendar, availability save, undo absence, account actions |
| Inline spinner | Sheets submitting |
| Alerts/dialogs | Geofence, early leave, discard dirty availability, delete account |
| Non-fatal refresh failure | Keep cached UI |

---

## 9. Accessibility (iOS baseline to match or exceed)

- Dynamic Type via system fonts (SwiftUI)
- SF Symbols with labels on tabs
- Reduce Motion respects login shake
- VoiceOver: ensure buttons have labels (Android: contentDescription / Semantics)
- Colour status pills must not be colour-only (status text)
- Touch targets for swipe alternatives via context menus / buttons

Android must meet TalkBack, large fonts, and Material a11y contrast as first-class acceptance criteria.

---

## 10. APIs & backend interactions (Staff)

### Firestore reads (staff session listeners)

| Collection | Filter |
|------------|--------|
| `users/{uid}` | Own doc |
| `shifts` | `staffId==uid`, `status==published`, date in staff window |
| `timesheets` | `staffId==uid` (+ client cutoff) |
| `messages` | `recipientId==uid`, last 30 days |
| `tasks` | `active==true` (UI filters assigned) |
| `task_completions` | date in shift window |
| `shift_attendance` | `staffId==uid`, date window |
| `daily_job_assignments` | `staffId==uid`, date window |
| `settings/app`, `settings/locations`, `settings/availabilityLocks` | Exact docs |
| `payslips` | On demand; own + submitted/archived + month |

### Firestore / Worker writes (Staff)

| Action | Target |
|--------|--------|
| Profile / lastLoginAt | `users/{uid}` allow-listed fields |
| Availability | Worker `POST /api/staff/availability` |
| Timesheet submit/resubmit/absence/undo | `timesheets/{id}` |
| Clock in/out | `shift_attendance/{shiftId}` |
| Task complete | Storage upload + `task_completions/{id}` |
| Daily job toggle | `daily_job_assignments/{id}` completed fields |
| Messages read | `messages/{id}.read=true` |
| Push token | `users/{uid}/notificationTokens/{id}` |
| Forced password complete | Worker `/api/complete-password-change` |
| Account deletion request | Worker `/api/account-deletion/request` |
| Staff action notify | Worker `/api/send-notification` (fire-and-forget) |

### Storage

- Upload: `task_photos/{uid}/{taskId}_{date}_{uuid}.jpg` (≤4, JPEG ≤2MB, max dim 1600)
- Read: manager `task_ref_photos/...` via download URL
- No staff delete/update of Storage objects

Full matrix: see `03-staff-permissions.md` and `05-cache-offline-security.md`.

---

## 11. Deep links & notification routing

`ViewModels/AppRouter.swift`

| Trigger | Staff destination |
|---------|-------------------|
| `?submit=<shiftId>` | Roster + SubmitHoursSheet |
| `?absent=<shiftId>` | Roster + ReportAbsenceSheet |
| path `roster` / `history` | Roster |
| path `tasks` / `job` | Tasks |
| path `availability` | Availability |
| path `account` | Account |
| path `home` | Home |
| event `timesheet-rejected` + id | Roster + submit |
| `timesheet-approved`, `roster-published`, `shift-changed`, `shift-cancelled` | Roster |
| `payslip-generated` | Account |
| local `shift-reminder` slot `submit-hours` / `forgot-end` | Submit sheet |
| other `shift-reminder` | Home |
| `timesheet-reminder` | Roster |

Manager-facing events are no-ops in Staff shell.

---

## 12. Offline behaviour summary

| Works offline | Needs network |
|---------------|---------------|
| Render cached roster/timesheets/messages/tasks/jobs | Login / password / email change |
| Device auth unlock | Availability save (Worker) |
| Local clock session + timer | Fresh payslip months |
| Previously downloaded payslip months | Task photo upload / completion write |
| Local shift reminders after schedule | Attendance verified sync |
| Legal screens, local profile photo | Account deletion request |
| Calendar `.ics` share fallback | First-time FCM registration |

Firestore persistent cache enabled (`FirebaseBootstrap`). No general offline write queue except clock session local persistence.

---

## 13. Caching strategy (iOS)

1. **Firestore disk cache** — primary offline source for listeners  
2. **In-memory repository state** — `@Published` collections for UI  
3. **Payslips** — session memory → disk cache → server; month markers in UserDefaults  
4. **Clock session** — UserDefaults (rules block early timesheet writes)  
5. **Task photos** — local sandbox; sweep before current week on staff session start  
6. **Optimistic UI** — limited (availability after Worker success; reminder cancel after write)  
7. **Manual refresh** — `refreshFromServer()` non-fatal on failure  

Android must improve toward Room + explicit invalidation (see roadmap) while preserving Firestore cache.

---

## 14. UI component catalogue (Staff-used)

| Component | Role |
|-----------|------|
| `ShiftCard` | Shift display + inline actions |
| `SubmitHoursSheet` / `ReportAbsenceSheet` | Timesheet actions |
| `WeekSelector` | Monday week navigation |
| `StatusPill` | Status chrome |
| `Toast` / `Banner` | Feedback |
| `EmptyStateView` | Empty lists |
| `CameraPicker` | Task proof capture |
| `TabScroll` | Consistent tab scrolling |
| `HoursMetrics` | Hour aggregates |
| `ShareSheet` | System share |
| Design tokens / Theme | Colours, spacing, glass gated iOS 26 |

Android: build Compose design system mirroring tokens, not pixel-copying iOS glass.

---

## 15. Documented gaps / gotchas (carry into Android)

1. **Absence timing:** follow `BusinessRules` + Firestore rules (submittable), not older staff-guide wording.  
2. **Email change Firestore fields:** verify live rules before porting.  
3. **Tasks / completions:** rules allow broader reads than UI shows (assigned filter is client-side). Do not widen Android UI; consider future rules harden separately.  
4. **Profile photo:** local-only on iOS today — do not invent cloud upload without product decision.  
5. **Passkey:** incomplete wiring — optional later.  
6. **staff-guide photo wording stale** — Storage upload is real.  
7. **Deep-link sheet attachment** — keep submit/absence hosts alive across navigation.  
8. **Managers must never enter Staff listeners with all-staff queries** in this app.

---

## 16. Staff must NOT access (summary)

Manager dashboard, all-staff roster publish/edit, staff management, wages/payroll admin, payslip generation, business settings writes, reports, task admin/redo, daily job template management, audit logs, other users’ private data. Full deny list: `03-staff-permissions.md`.

---

## 17. Audit completion criteria

- [x] Every Staff screen inventoried  
- [x] Navigation + tabs documented  
- [x] Auth gates documented  
- [x] Roster / timesheet / availability / tasks / notifications / account / payslips covered  
- [x] Permissions, local storage, offline, cache, haptics, empty/loading/error covered  
- [x] APIs / Firestore / Storage / Worker covered  
- [x] Explicit Staff deny list started  
- [x] Gaps between docs and code called out  

**Phase 1 complete.** Proceed to structure / permissions / notifications / cache docs, then Phase 2 roadmap — **no Android feature coding until roadmap Phase A0 kickoff is approved.**
