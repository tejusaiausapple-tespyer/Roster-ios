# agents.md — AI Agent Context for Rosterra

> **PURPOSE**: This file provides ALL context an AI agent needs to understand, modify, debug, or extend the Rosterra iOS project. AI agents MUST read this file first and update it when making structural changes.

---

## Last Updated

2026-07-07 by AI agent (accuracy pass: Rosterra rename, manager Tasks + Wage now built,
added shift_attendance / daily-jobs / wages collections, manager tabs, single-tenant note).

---

## Project Identity

| Field | Value |
|-------|-------|
| Name | Rosterra (Xcode target, project, and app display name — unified 2026-07-15; see `docs/BRANDING.md`) |
| Type | Native iOS app (SwiftUI) |
| Platform | iOS 17.0+, iPhone + iPad + Mac Catalyst |
| Language | Swift 5.0 |
| Bundle ID | `com.surainvestments.roster` |
| Build System | Xcode + XcodeGen (`project.yml`) |
| Package Manager | Swift Package Manager (SPM) |
| Backend | Firebase (Auth, Firestore, Storage) + Cloudflare Worker API |
| API Domain | `https://sura-roster.com` |
| Timezone | Australia/Adelaide (hardcoded in `RosterCalendar`) |
| Week Start | Monday (ISO 8601) |

---

## What This App Does

Rosterra is a staff rostering and scheduling app for a single business (Sura Investments Pty Ltd). It has two user roles:

1. **Staff** — View assigned shifts, submit worked hours (timesheets), manage weekly availability, complete assigned tasks with photo proof, view messages/notifications.
2. **Manager** — Create/edit/publish shifts, approve/reject timesheets, view dashboard metrics, manage the roster across all staff.

Both roles share a single codebase. The app routes to the correct UI based on `AppUser.role` after login.

> **Tenancy (deliberate):** the app is **intentionally single-tenant** — one business per
> Firebase project, so there is no `businessId`/tenant partition key in the models or Firestore
> rules. Multi-tenant scoping is deferred to the future SaaS phase (do not add `businessId`
> plumbing until then). Access control is role-based (`isManager()` in the deployed rules),
> not tenant-based.

---

## Architecture Overview

```
RosterraApp (entry point)
└── RootView (auth state router)
    ├── LoginView (unauthenticated)
    ├── MainTabView (staff role)
    │   ├── HomeView
    │   ├── RosterView (→ pushes HistoryView via "View Shift History").
    │   │     GOTCHA: the `.task(id: router.pendingSubmitShiftId/…AbsentShiftId)`
    │   │     deep-link handlers and the SubmitHours/ReportAbsence sheets MUST
    │   │     stay attached to the NavigationStack itself, not its root content
    │   │     — a pushed HistoryView marks the root disappeared, so tasks/sheets
    │   │     on it never fire (broke Resubmit-after-rejection; fixed 2026-07-05)
    │   ├── TasksView
    │   ├── AvailabilityView
    │   └── AccountView
    └── ManagerMainView (manager role)
        ├── ManagerDashboardView
        ├── ManagerRosterView
        ├── ManagerTimesheetsView
        ├── ManagerStaffView
        ├── ManagerAvailabilityView
        ├── ManagerReportsView
        ├── ManagerTenureView
        ├── ManagerWageView
        ├── ManagerPayrollView
        ├── ManagerTasksView
        ├── ManagerSettings (Locations, Company Details)
        └── ManagerAccountView
```

### Layer Structure

```
Rosterra/
├── App/                    # Entry point, AppDelegate, RootView
├── Models/                 # Data models (Shift, Timesheet, User, etc.)
├── Services/               # Firebase, Auth, API, Calendar, etc.
├── ViewModels/             # AuthViewModel, AppRouter
├── Features/               # All UI views, organized by domain
│   ├── Auth/               # Login, password change, profile completion
│   ├── Home/               # Staff home screen + notifications
│   ├── Shell/              # MainTabView (staff tab bar)
│   ├── Roster/             # Staff roster view
│   ├── Availability/       # Staff availability management
│   ├── History/            # Timesheet history
│   ├── Tasks/              # Staff task completion
│   ├── Account/            # Staff account/settings
│   ├── Shared/             # Reusable view components (ShiftCard, sheets, AppVersionHistoryView)
│   └── Manager/            # All manager-side views
│       ├── Dashboard/      # (+ DailyJobAssignSheet)
│       ├── Roster/
│       ├── Timesheets/     # (+ Verified Attendance card)
│       ├── Staff/
│       ├── Availability/
│       ├── Reports/
│       ├── Tenure/         # Tenure & Hours MVP (TenureMetrics + ManagerTenureView)
│       ├── Tasks/          # manager task management (list/editor/review)
│       ├── Wage/           # wages module (awards, earnings lines, profiles)
│       ├── Payroll/        # payroll module (weekly payslips, PDF, workflow)
│       ├── Settings/       # Locations + Company Details
│       └── Shell/          # Manager tab bar + navigation
├── DesignSystem/           # Theme + reusable UI components
│   ├── Theme.swift
│   └── Components/
└── Resources/              # Assets, Info.plist, entitlements, GoogleService-Info.plist
```

---

## Key Files Reference

### App Lifecycle
| File | Purpose |
|------|---------|
| `App/RosterraApp.swift` | `@main` entry point, configures Firebase, injects `RosterRepository` + `AuthViewModel` |
| `App/AppDelegate.swift` | UIKit app delegate for push notification registration |
| `App/RootView.swift` | Auth state router — renders the screen chosen by `AppRoute` |
| `App/AppRoute.swift` | Pure routing decision (unit-tested): setup → restoring → login → profileLoading → forcedPasswordChange → profileCompletion → deviceAuthGate → manager/staff main. Gates apply to BOTH roles |

### Auth Features (in `Features/Auth/`)
| File | Purpose |
|------|---------|
| `LoginView.swift` | Email/password login with biometric quick-login option |
| `ChangePasswordView.swift` | Password change (forced or voluntary) with validation rules |
| `ChangeEmailView.swift` | Email change with reauthentication |
| `ProfileCompletionView.swift` | Enforced profile completion (DOB, address, phone) |
| `DeviceAuthGateView.swift` | Biometric/passcode lock screen |
| `SetupRequiredView.swift` | Shown when `GoogleService-Info.plist` is missing from the bundle (developer setup screen) |
| `ManagerBlockedView.swift` | **Unused/legacy** — managers now get the native `ManagerMainView`; locked accounts are signed out at login instead |

### Models (all in `Models/`)
| File | Key Types |
|------|-----------|
| `User.swift` | `AppUser` — full user profile with role, status, availability, employment type |
| `Shift.swift` | `Shift` — rostered shift with date, times, break, location, status |
| `Timesheet.swift` | `Timesheet` — submitted hours linked to a shift |
| `Availability.swift` | `DayAvailability`, `Weekday`, `UserAvailability` — weekly availability pattern |
| `Message.swift` | `Message` — manager-to-staff notification messages |
| `RosterTask.swift` | `RosterTask`, `TaskCompletion` — recurring/one-off tasks with completion tracking |
| `Enums.swift` | `UserRole`, `UserStatus`, `EmploymentType`, `ShiftStatus`, `TimesheetStatus`, `StaffShiftDisplayStatus` |
| `BusinessRules.swift` | All business logic constants and functions (shift windows, submission rules, password validation) |
| `RosterCalendar.swift` | Date/calendar utilities (Australia/Adelaide timezone, Monday-start weeks) |
| `RosterFormat.swift` | Formatting helpers for dates, times, hours display |
| `FirestoreValue.swift` | `FS` enum — safe Firestore document field extraction |
| `AppSettings.swift` | `AppSettings` — company name from Firestore |
| `AppRelease.swift` | `AppRelease` struct + `ReleaseHistory` enum — static in-app release registry (version, build, date, features, bug fixes, commit hash). `ReleaseHistory.current` returns the latest entry; `ReleaseHistory.all` is the full history newest-first. To add a release: prepend to `all` and bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml`. |
| `RosterLocation.swift` | `RosterLocation` — manager-defined work location (suburb + AU state + auto capital city). Stored as an array on `settings/locations`; `shifts.location` stays a plain string (`"Suburb, STATE"`) for PWA compatibility |

### Services (all in `Services/`)
| File | Purpose |
|------|---------|
| `RosterRepository.swift` | **Core data layer** — Firestore real-time listeners, all CRUD operations, @Observable for SwiftUI |
| `AuthService.swift` | Firebase Auth wrapper (sign in/out, password reset, change password) |
| `WorkerAPIClient.swift` | Cloudflare Worker API calls (save availability, complete password change, send notifications) |
| `DeviceAuthService.swift` | Biometric/passcode local authentication gate |
| `BiometricCredentialStore.swift` | Stores login credentials behind biometric protection |
| `PasskeyManager.swift` | Apple Passkey registration/sign-in (local presence gate) |
| `CalendarService.swift` | Add shifts to iOS Calendar (EventKit) or generate ICS files |
| `KeychainHelper.swift` | Keychain read/write/delete operations |
| `FirebaseBootstrap.swift` | Firebase initialization + Firestore configuration |
| `AppConfig.swift` | Static config (API URL, relying party, timeouts) |
| `TaskPhotoCache.swift` | Local file system cache for task completion photos |
| `Haptics.swift` | Haptic feedback convenience methods |
| `NotificationService.swift` | Registers/syncs FCM push tokens (`fcmToken` + `notificationTokens` subcollection on the user doc). Push delivery enabled 2026-07-15; no longer gated on the Apple Developer account. Local "backup" alerts (timesheet decision/roster-published) were removed 2026-07-19 — server push is the only path now (see `docs/ROADMAP-PROGRESS.md`'s notification audit remediation entry) |
| `AddressSearchCompleter.swift` | MapKit address autocomplete for profile |

### ViewModels
| File | Purpose |
|------|---------|
| `AuthViewModel.swift` | Login/logout state machine, biometric quick-login, handles auth flow |
| `AppRouter.swift` | Navigation state for programmatic routing |

---

## Data Flow

### Authentication Flow
1. `RosterraApp` configures Firebase and creates `AuthViewModel` + `RosterRepository`
2. `RootView` observes `AuthViewModel.state` (enum: `.loading`, `.unauthenticated`, `.authenticated`)
3. On successful login → `RosterRepository.start(uid:)` begins Firestore listeners
4. Role-based routing: `AppUser.role == .manager` → `ManagerMainView`, else → `MainTabView`
5. Optional gates: `DeviceAuthGateView` (biometric), `ProfileCompletionView` (missing profile data), `ChangePasswordView` (forced)

### Data Layer (RosterRepository)
- **Pattern**: `@MainActor @Observable` class injected via SwiftUI `.environment()`
- **Listeners**: Real-time Firestore `onSnapshot` for shifts, timesheets, messages, tasks, task completions, user profile, app settings
- **Role Awareness**: Manager gets all-staff data (shifts windowed to the ±shift window, timesheets windowed to `submittedAt` ≥ 90 days back, users unwindowed); Staff gets only own data. Tasks + task completions listeners are shared by both roles (all active tasks; all completions in the shift date window — no per-user filter).
- **Key Collections**: `shifts`, `timesheets`, `users` (+ `notificationTokens` subcollection), `messages`, `tasks`, `task_completions`, `shift_attendance`, `daily_job_templates`, `daily_job_assignments`, `wages`, `payslips`, `settings` (docs `app` / `locations` / `availabilityLocks`)
- **Write Operations**: Submit/resubmit timesheets, report absence, update profile, save availability, complete tasks, manager CRUD for shifts/timesheets

### API Layer (WorkerAPIClient)
- Authenticates with Firebase ID token (Bearer header)
- Base URL: `https://sura-roster.com`
- Endpoints: `POST /api/staff/availability`, `POST /api/complete-password-change`, `POST /api/send-notification`

---

## Firestore Collections

| Collection | Document ID | Used By | Key Fields |
|------------|-------------|---------|------------|
| `users` | Firebase UID | Both | fullName, email, role, status, employmentType, weeklyAvailability, mustChangePassword, needsSetup |
| `shifts` | Auto-generated | Both | staffId, date (yyyy-MM-dd), rosteredStart, rosteredEnd, breakMinutes, scheduledHours, status, location |
| `timesheets` | Auto-generated | Both | shiftId, staffId, actualStart, actualEnd, actualBreakMinutes, workedHours, status, managerNotes |
| `messages` | Auto-generated | Both | senderId, recipientId, body, sentAt, expiresAt, read |
| `tasks` | Auto-generated | Both | title, description, frequency, date, dayOfWeek, active, managerPhotoUrl, assignedTo, dueTime, priority, requiresPhoto |
| `task_completions` | `{taskId}_{date}` | Both | taskId, date, completed, completedAt, completedBy, staffPhotoUrl / staffPhotoUrls (`gs://...` for new iOS proof photos; legacy HTTPS URLs still supported), status, redoReason, reviewedBy/At, managerDownloadedAt |
| `shift_attendance` | `{shiftId}` | Both | shiftId, staffId, date, clockInAt/clockOutAt (server timestamps), clockInDeviceAt/clockOutDeviceAt, GPS fixes + geofence verdict/distance. Append-only audit trail (see `docs/shift-attendance.md`) |
| `daily_job_templates` | Auto-generated | Manager | title, active, createdAt, createdBy — permanent reusable job library (see `docs/daily-jobs-feature.md`) |
| `daily_job_assignments` | `{shiftId}_{templateId}` | Both | shiftId, staffId, templateId, title, date, assignedAt/By, completed, completedAt/By |
| `payslips` | `{periodStart}_{staffId}` (corrections `_c{n}`) | Both | weekly payslip snapshots: staff/award/rate snapshot + `employeeId`, hour buckets + rates, extra earnings, PAYG/deductions, super %, status (draft/under_review/approved/submitted/archived), audit[]. Staff read own **submitted/archived only** (rules deployed 2026-07-10). Managers stream a rolling window; staff do NOT stream — Account → Payslips fetches one month at a time via `staffPayslips(monthKey:)` (cache-first: session memory → Firestore disk cache → server; the doc-id range rides on the `{periodStart}_` prefix so no composite index is needed) |
| `wages` | Auto-generated | Manager only | awards (classifications), earnings lines (rate types + super/tax), per-staff wage profiles. **Unreadable by staff** under deployed rules |
| `settings` | `app` / `locations` / `availabilityLocks` | Both (read) / Manager (write) | companyName + ABN/address; manager work locations; roster availability week locks |
| `users/{uid}/notificationTokens` | Auto-generated | Owner | token, platform, userAgent, enabled — FCM push tokens |

> Rules also define `auditLogs`, `masterSheets`, and `importBatches`, but those are
> **web/Worker-only** collections — the iOS app does not read or write them.

---

## Business Rules (from `BusinessRules.swift`)

| Rule | Value |
|------|-------|
| Break range | 0–90 minutes, step 5 |
| Shift window (staff view) | 28 days back, 56 days forward |
| Manager timesheet listener window | 90 days back (`managerTimesheetWindowDaysBack`) — keeps the all-staff live listener fast; staff keep own 5-year history |
| Availability edit range | -2 to +12 weeks from current |
| Week start | Monday |
| Timezone | Australia/Adelaide |
| Timesheet submittable | After shift end time (`submittableAfter` or computed from rostered end) |
| Password requirements | 8+ chars, 1 uppercase, 1 digit (a symbol is *recommended* in the UI checklist but not required — see `BusinessRules.passwordErrors`) |
| Staff can report absence | Before shift becomes submittable AND no approved timesheet exists |
| Staff can submit hours | After shift end AND shift is published AND no approved/absent timesheet |

---

## Behaviors To Know (undocumented elsewhere)

- **7-day forced manual login**: quick sign-in (Face ID / passkey) is refused if the last *manual* password login was more than 7 days ago (`roster_last_manual_login_date` in UserDefaults, checked in `LoginView`; also reset by `VerifyPasswordSheet`).
- **`AuthViewModel.temporaryPassword`**: the plaintext password is held in memory after a manual login so the Account tab can enable Face ID without re-prompting. It is cleared when Face ID is enabled or on logout.
- **Background re-lock**: with device auth enabled, returning from ≥2 minutes in the background re-requires biometric unlock (`AppConfig.deviceAuthBackgroundRelock`).
- **Timesheet doc id == shift id** for staff-created timesheets (1:1); manager operations reference `timesheet.id` directly.
- **Timesheet writes set `submittedAt` (server timestamp)** — the manager's 90-day windowed listener depends on this field existing on every timesheet.
- **`saveShift` MUST write `shiftStartAt` + `submittableAfter` (Timestamps)** — the deployed Firestore rules refuse staff timesheet create/update unless the shift doc has `submittableAfter is timestamp`, and the Worker's shift-start/hours-reminder crons key off both fields. Recomputed on every save.
- **Notification event names use hyphens** (from the Worker's `NOTIFICATION_EVENTS` registry in `worker/handlers/notifications.ts` — treat that live file as the source of truth, not a list here; a stale local mirror of it, `docs/reference/worker-notifications.ts`, was retired 2026-07-19 for exactly this reason). This repo sends: `roster-published` (single + bulk publish, `RosterRepository.swift`'s `publishShift`/`publishAllDrafts`), submit/absence + `shift-started`/`shift-ended` (staff, on attendance actions), `message-task` on Tasks-tab create/assignee change. `AppRouter.swift`'s `handleNotificationUserInfo`/`managerTab(forEvent:)` is the authoritative list of every event this app *routes* on tap, staff and manager.
- **Deployed Firestore rules**: `Roster PWA/firestore.rules` (sibling repo) is the actual live source of truth — it's what gets `firebase deploy --only firestore:rules`'d. **`docs/reference/firestore.rules.deployed` in THIS repo is a manually-maintained snapshot that goes stale** (confirmed 2026-07-17: it was missing the entire ATO-safe account-deletion rule block and the `ios-native`/`android-native` notificationTokens platform values, both added to the real file on 2026-07-16, two commits before this was caught). Treat the reference copy as a convenience read, not authoritative — diff it against the sibling repo's live file before trusting a claim about "what's deployed," and re-sync it after every rules change (see `docs/reference/firestore.rules.payroll-proposed.md` for the sync step this keeps getting skipped).
- **Firebase Storage rules reference copy**: `docs/reference/storage.rules`. Staff proof photos upload to `task_photos/{uid}/...` and store `gs://...` references in `staffPhotoUrl`; manager review downloads through the Firebase Storage SDK. Manager reference photos remain HTTPS download URLs so staff can load task instructions with `AsyncImage`.
- **`RosterRepository.liveHourlyRate(forStaffId:shiftDateKey:)`** (2026-07-17) is now the only correct way to price a shift/hour for LIVE displays (Roster's cost chip, Reports, Timesheet detail) — it consults the real wage-profile model (`StaffWageProfile.loadedRate`, same precedence as payroll generation, day-of-week-aware weekend rate) before falling back to `user.hourlyRate ?? BusinessRules.defaultHourlyRate`. Previously these three screens each did `user.hourlyRate ?? 25.0` directly, silently ignoring any assigned wage profile — never call that pattern again; always go through `liveHourlyRate`.

---

## Design System

### Theme (`DesignSystem/Theme.swift`)
- Colors defined with light/dark variants using `Color(UIColor { traitCollection in ... })`
- Brand: indigo `#4F46E5` / `#6366F1`
- Accent: green `#10B981` / `#34D399`
- Surfaces: background, card, separator
- Text: primary, secondary, tertiary
- Status styles: pending (amber), approved (green), rejected (red), draft (gray), absent (purple)
- Corner radii: small (8), medium (12), large (16)
- Layout constants: `maxContentWidth` (1400), `minColumnWidth` (168)
- **Liquid Glass helpers (2026 UI)**: `glassSurface(in:tint:interactive:)`, `glassCapsule(tint:interactive:)`, `glassProminentSurface(in:tint:)`. Reserved for the navigation layer (bars, control clusters, floating buttons) — never content. Gated by `#if compiler(>=6.2)` + `if #available(iOS 26.0, *)`, with an `.ultraThinMaterial` fallback for iOS 17–25. The app deploys to iOS 17 but adopts real Liquid Glass automatically on iOS/iPadOS/macOS 26+.

### Reusable Components (`DesignSystem/Components/`)
| Component | Purpose |
|-----------|---------|
| `Buttons.swift` | PrimaryButtonStyle, SecondaryButtonStyle, InlinePillButtonStyle |
| `GlassCard.swift` | Card and GlassCard with optional accent stripe |
| `WeekSelector.swift` | 7-day week strip with navigation arrows |
| `StatusPill.swift` | Compact status badge with colored dot |
| `Banner.swift` | Info/warning/error/success inline banner |
| `Toast.swift` | Transient top-of-screen toast messages |
| `StatTile.swift` | Metric tile (value + label) |
| `Skeleton.swift` | Loading shimmer placeholders |
| `EmptyStateView.swift` | Empty state with icon + message + action |
| `SectionHeader.swift` | Section title with optional trailing view |
| `CameraPicker.swift` | Camera/photo library picker for task photos |
| `ScreenTitlePill.swift` | Navigation bar pill-shaped title |

---

## Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| firebase-ios-sdk | Latest | Auth, Firestore, Storage |

Defined in `project.yml` under `packages:` using the Firebase GitHub URL.

---

## Current State & Known Limitations

### Working Features
- ✅ Staff login with email/password
- ✅ Biometric/passcode quick-login
- ✅ View rostered shifts with week navigation
- ✅ Submit/resubmit worked hours (timesheets)
- ✅ Report absence for shifts
- ✅ Weekly availability management
- ✅ Task completion with photo evidence
- ✅ View notification messages
- ✅ Timesheet history with filters
- ✅ Add shifts to iOS Calendar
- ✅ Manager dashboard with live metrics
- ✅ Manager roster management (create/edit/delete/publish shifts)
- ✅ Manager roster — adaptive iPad/Mac week-grid with 2026 Liquid Glass, drag move/copy (drafts only; published shifts locked), bulk delete by all-staff/per-staff with week-based visibility rules, dynamic week label, week-aware add-shift default date
- ✅ Manager timesheet approval/rejection — week-based single full-width view (week selector + glass status/staff filters + adaptive card grid + bottom summary), detail as a sheet; glass approve/reject
- ✅ Manager Staff directory (searchable, status filters). Detail edits are **per-field** — pencil to unlock, checkmark to save just that field via `repo.updateStaffFields(staffId:, [key:value])` (direct `users/{id}` write; needs manager-write Firestore rules). **Email = request-and-self-confirm**: manager taps "Ask {name} to change their email" → `repo.requestStaffEmailChange` sets `emailChangeRequired`; staff sees a banner in Account → `ChangeEmailView` (`verifyBeforeUpdateEmail`, Firebase link) → clears the flag. Also "require new address" → `repo.requestStaffAddressUpdate` → `ProfileCompletionView` gate (with Sign out).
- ✅ Manager Availability (week selector; staff × 7-day matrix on iPad/Mac, per-staff cards on iPhone)
- ✅ Manager Reports (weekly analytics: scheduled/worked hours, labour cost + super, timesheet status, per-staff breakdown)
- ✅ Manager Tasks management (create/edit/assign tasks, live completion review, request-redo flow, photo lifecycle)
- ✅ Manager Wage module (Xero-AU-style awards + classifications, earnings lines, per-staff wage/super profiles; manager-only `wages` collection)
- ✅ Payroll module (2026-07-10): weekly draft payslips auto-generated (client-side, idempotent, first manager session on/after Monday) from approved timesheets + wage assignments; manager-only review→edit→approve→submit workflow (staff see payslips ONLY after Submit); live A4 AU-style PDF (`PayslipPDFService`, same renderer for preview + export); corrected-copy flow for submitted payslips; audit trail on-doc + `auditLogs`; staff Account → Payslips page. Firestore `payslips` rules deployed 2026-07-10 — ⏳ device verification pending
- ✅ Daily Jobs (manager per-shift job assignments from the roster; library add/delete; staff Complete/Undo via the Home bell panel)
- ✅ Verified shift attendance (server-timestamped clock-in/out + GPS/geofence capture; manager Verified Attendance card)
- ✅ Device auth gate (biometric lock)
- ✅ Forced password change flow
- ✅ Profile completion flow

### Not Yet Implemented / Disabled
- ❌ Push **delivery** (FCM token registration/sync is live, but end-to-end delivery waits on
  a paid Apple Developer account / APNs — see `docs/WHEN_DEVELOPER_ACCOUNT_READY.md`)
- ✅ Manager **Tenure & Hours** (`ManagerTenureView` + `TenureMetrics`) — service tenure from first approved shift, approved hours, KPIs, detail sheet (exports deferred)
- ✅ **ATO-safe account deletion** — request/approve/cancel + 30-day Auth purge; retains identity/TFN/timesheets/payslips (`docs/APP_STORE_SUBMISSION.md`)
- ❌ Passkey-based auth (code exists but not wired into main flow)

> Previously listed here but now BUILT (2026-07-06/07): **Manager Tasks management UI**
> (`Features/Manager/Tasks/` — list/editor/review + redo flow) and the **Manager Wage module**
> (`Features/Manager/Wage/ManagerWageView.swift`, `Models/WageModels.swift`). See Working
> Features above.

---

## File Naming Conventions

- Views: `{Feature}View.swift` (e.g., `RosterView.swift`, `ManagerDashboardView.swift`)
- Sheets/modals: `{Feature}Sheet.swift` (e.g., `SubmitHoursSheet.swift`, `DayEditSheet.swift`)
- Models: Named after the entity (e.g., `Shift.swift`, `User.swift`)
- Services: Named after the concern (e.g., `AuthService.swift`, `CalendarService.swift`)
- Manager views: Prefixed with `Manager` (e.g., `ManagerRosterView.swift`)

---

## How to Modify This Project

### Adding a New Staff Feature
1. Create view(s) in `Features/{FeatureName}/`
2. Add any new models to `Models/`
3. Add Firestore operations to `RosterRepository.swift`
4. Add tab/navigation in `Features/Shell/MainTabView.swift`
5. Update this `agents.md` file

### Adding a New Manager Feature
1. Create view(s) in `Features/Manager/{FeatureName}/`
2. Add tab case to `ManagerTab` enum in `Features/Manager/Shell/ManagerNavigation.swift`
3. Wire up in `Features/Manager/Shell/ManagerMainView.swift`
4. Add Firestore operations to `RosterRepository.swift` (uses role-based listeners)
5. Update this `agents.md` file

**2026 UI conventions for new manager tabs (match `ManagerRosterView`):**
- Drive layout from **measured container width** (via `GeometryReader`), not size class alone, so Split View / Slide Over / resized Mac windows behave. Reuse a compact layout below ~720pt.
- Center wide content at `Theme.maxContentWidth`; avoid horizontal scrolling for primary content.
- Apply **Liquid Glass** only to the navigation layer (bars, control clusters, floating buttons) using the `Theme` glass helpers (`glassCapsule`, `glassProminentSurface`, `glassSurface`); keep lists/cards solid.
- **Footer pills / summary bars: always use dark text** (`Theme.textPrimary`), never `textSecondary`/`textTertiary`. Glass/translucent footers wash out light text, so keep footer chip labels dark for legibility (see the Roster and Timesheets bottom summary bars). Prefer a **fixed footer** (in the layout `VStack`) over a translucent `.safeAreaInset` bar when content would otherwise scroll under and show through.
- **One sheet per view.** Do NOT attach multiple `.sheet` / `.sheet(item:)` modifiers to the same view — SwiftUI presents them unreliably (slow, or sometimes never until an app restart). Use a single `.sheet(item:)` driven by one `Identifiable` enum with a case per destination (see `ManagerRosterView.ActiveSheet` for create vs edit).
- Respect `accessibilityReduceMotion` for custom animations; add accessibility labels to icon-only buttons.
- New Swift files must be added to the Xcode target — this project uses **explicit file refs in `project.pbxproj`** (XcodeGen, no file-system sync). Either run `xcodegen generate` after adding files, or place shared helpers in an already-referenced file (that's why the glass helpers live in `Theme.swift`).

### Adding a New Firestore Collection
1. Define model struct in `Models/` with `init?(id:data:)` using `FS` helpers
2. Add listener in `RosterRepository.start(uid:)` with `onSnapshot`
3. Add `@Published`/stored property to `RosterRepository`
4. For manager (all-staff) listeners, **scope by a date window** where possible (see the shifts listener and `managerTimesheetWindowDaysBack`) to keep them fast as collections grow
5. Update this `agents.md` file

### Modifying Business Rules
1. All rules are centralized in `Models/BusinessRules.swift`
2. Constants at the top, computed functions below
3. The web app's `src/lib/utils.ts` should stay in sync

---

## Environment & Setup

### Prerequisites
- macOS with Xcode 15+
- `GoogleService-Info.plist` in `Rosterra/Resources/` (not in git)
- Firebase project with Auth + Firestore + Storage enabled
- Cloudflare Worker deployed at `sura-roster.com`

### Build
```bash
# Generate Xcode project from project.yml (if using XcodeGen)
xcodegen generate

# Open in Xcode
open Rosterra.xcodeproj
```

### Key Config Files
| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project definition |
| `Resources/GoogleService-Info.plist` | Firebase config (gitignored) |
| `Resources/Info.plist` | iOS app metadata |
| `Resources/Rosterra.entitlements` | **Keychain Sharing** (`keychain-access-groups`) — required for Firebase Auth on macOS/Mac Catalyst; wired via `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Associated Domains (passkeys) + `aps-environment` (push) are live as of 2026-07-15 under paid team `GS2KGPX9P8`. |

---

## AI Agent Instructions

When working on this project:

1. **Always read this file first** to understand the project structure
2. **Use the existing patterns** — don't introduce new architectures or libraries
3. **Follow the Theme** — use `Theme.brand`, `Theme.card`, etc. for all colors
4. **Use `FS` helpers** for Firestore document parsing (never force-cast)
5. **Add to `RosterRepository`** for any new data operations
6. **Keep timezone-aware** — always use `RosterCalendar` for date operations
7. **Update this file** when adding new features, models, or services
8. **Match existing naming** — `{Feature}View.swift`, `{Feature}Sheet.swift`
9. **iPad support** — views should work on both iPhone and iPad (use `UIDevice.current.userInterfaceIdiom` checks where layout differs)
10. **Accessibility** — use semantic labels, dynamic type support via the Theme text styles

---

## Contact & Ownership

- **Developer**: Sura (sole developer)
- **Business**: Sura Investments Pty Ltd
- **Domain**: sura-roster.com
