# Architecture — How Staff and Manager Sides Connect

> This document explains the shared infrastructure, data flow between roles, and how the two-sided app works as a unified system.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        RosterStaff iOS App                        │
├──────────────────────────┬──────────────────────────────────────┤
│      Staff UI            │         Manager UI                    │
│  (MainTabView)           │    (ManagerMainView)                  │
│  - HomeView              │    - ManagerDashboardView             │
│  - RosterView            │    - ManagerRosterView                │
│    (→ HistoryView)       │    - ManagerTimesheetsView            │
│  - TasksView             │    - ManagerStaffView                 │
│  - AvailabilityView      │    - ManagerAvailabilityView          │
│  - AccountView           │    - ManagerReportsView               │
│                          │    - ManagerAccountView               │
├──────────────────────────┴──────────────────────────────────────┤
│                    Shared Layer                                   │
│  AuthViewModel • RosterRepository • Models • DesignSystem        │
├─────────────────────────────────────────────────────────────────┤
│                    Services Layer                                 │
│  AuthService • WorkerAPIClient • DeviceAuthService • etc.        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
        ┌──────────┐ ┌──────────┐ ┌────────────────┐
        │ Firebase │ │ Firebase │ │  Cloudflare    │
        │   Auth   │ │Firestore │ │  Worker API    │
        └──────────┘ └──────────┘ └────────────────┘
```

---

## The Connection Point: RosterRepository

The `RosterRepository` (`Services/RosterRepository.swift`) is the **single source of truth** that both sides share. It's a `@MainActor @Observable` class injected into the entire SwiftUI view hierarchy via `.environment()`.

### Role-Based Behavior

When `start(uid:)` is called, the repository reads the user document to determine their role, then sets up **different Firestore listeners** based on that role:

```
RosterRepository.start(uid:)
    │
    ├── SHARED listeners (both roles, attached immediately):
    │   ├── Listen: users/{uid} (own profile; role read from here)
    │   ├── Listen: tasks WHERE active == true
    │   ├── Listen: task_completions WHERE date IN shift window (−28…+56 days)
    │   │           (no per-user filter — both roles see all completions in window)
    │   ├── Listen: settings/app (companyName / ABN / address)
    │   ├── Listen: settings/locations (manager work locations + geofences)
    │   └── Listen: settings/availabilityLocks (locked roster weeks)
    │
    └── ROLE listeners (attached once the user doc arrives):
        │
        ├── If role == .staff:
        │   ├── Listen: shifts WHERE staffId == uid AND status == "published"
        │   │           AND date IN shift window (−28…+56 days)
        │   ├── Listen: timesheets WHERE staffId == uid
        │   │           (client-side filtered to submittedAt ≥ 5 years back)
        │   ├── Listen: messages WHERE recipientId == uid AND sentAt ≥ 30 days back
        │   ├── Listen: shift_attendance WHERE staffId == uid (own verified clock-in/out)
        │   └── Listen: daily_job_assignments WHERE staffId == uid AND date IN shift window
        │
        └── If role == .manager:
            ├── Listen: shifts WHERE date IN shift window (−28…+56 days) — all staff, all statuses
            ├── Listen: timesheets WHERE submittedAt ≥ 90 days back — all staff
            ├── Listen: users (ALL) → populates allUsers
            ├── Listen: shift_attendance (all records in the shift window)
            ├── Listen: daily_job_templates (permanent job library) + daily_job_assignments (window)
            └── Listen: wages (manager-only — awards, earnings lines, staff wage profiles)
```

### Shared Properties (both roles use)

| Property | Type | Description |
|----------|------|-------------|
| `currentUser` | `AppUser?` | The logged-in user's profile |
| `shifts` | `[Shift]` | Shifts (filtered for staff, all for manager) |
| `timesheets` | `[Timesheet]` | Timesheets (filtered for staff, all for manager) |
| `messages` | `[Message]` | Messages for the user |
| `tasks` | `[RosterTask]` | Active tasks |
| `taskCompletions` | `[TaskCompletion]` | Completion records |
| `appSettings` | `AppSettings` | Company name and global settings |
| `isLoading` | `Bool` | Loading state |
| `loadError` | `String?` | Error message |

### Manager-Only Properties

| Property | Type | Description |
|----------|------|-------------|
| `allUsers` | `[AppUser]` | All staff members (for name resolution, staff picker) |
| `wageAwards` | `[WageAward]` | Xero-AU-style pay awards + classifications (manager-only `wages` collection) |
| `earningsLines` | `[EarningsLine]` | Earnings lines with rate types + super/tax flags |
| `staffWageProfiles` | `[StaffWageProfile]` | Per-staff wage/super profiles |
| `locations` | `[RosterLocation]` | Manager-defined work locations (`settings/locations`) |
| `lockedAvailabilityWeeks` | `Set<String>` | Roster weeks whose staff availability the manager has locked (`settings/availabilityLocks`) |

> Both-role properties added since this doc was first written: `attendanceRecords`
> (`[ShiftAttendance]`), `dailyJobTemplates` (`[DailyJobTemplate]`, manager-loaded),
> `dailyJobAssignments` (`[DailyJobAssignment]`). Staff stream only their own attendance /
> assignments; managers stream all in the shift window.

---

## Data Flow: Staff → Manager

This is how staff actions flow to the manager and how manager actions flow back to staff:

### Staff Submits Hours → Manager Approves

```
STAFF                               FIRESTORE                          MANAGER
  │                                     │                                │
  │ submitTimesheet(shift, hours)        │                                │
  ├────────────────────────────────────► │                                │
  │                                     │ timesheets/{id} created         │
  │                                     │ status: "pending"               │
  │                                     │                                │
  │                                     │ onSnapshot fires ──────────────►│
  │                                     │                                │
  │                                     │                  approveTimesheet│
  │                                     │◄────────────────────────────────┤
  │                                     │ status: "approved"              │
  │                                     │ approvedBy: managerUid          │
  │ onSnapshot fires                    │ approvedAt: now                 │
  │◄────────────────────────────────────│                                │
  │ (shift status updates in UI)        │                                │
```

### Manager Creates Shift → Staff Sees It

```
MANAGER                             FIRESTORE                          STAFF
  │                                     │                                │
  │ saveShift(data, nil) [create]       │                                │
  ├────────────────────────────────────► │                                │
  │                                     │ shifts/{id} created             │
  │                                     │ status: "draft"                 │
  │                                     │                                │
  │ publishAllDrafts(weekStartKey)      │                                │
  ├────────────────────────────────────► │                                │
  │                                     │ status → "published"            │
  │                                     │                                │
  │                                     │ onSnapshot fires ──────────────►│
  │                                     │                   (staff sees    │
  │                                     │                    new shift)    │
```

### Staff Reports Absence → Manager Sees It

```
STAFF                               FIRESTORE                          MANAGER
  │                                     │                                │
  │ reportAbsence(shift, reason)        │                                │
  ├────────────────────────────────────► │                                │
  │                                     │ timesheets/{id} created         │
  │                                     │ status: "absent_reported"       │
  │                                     │                                │
  │                                     │ onSnapshot fires ──────────────►│
  │                                     │              (appears in manager │
  │                                     │               timesheets view)   │
```

---

## Shared Models

Both sides use the exact same data models. There is no separate "manager model" vs "staff model":

| Model | Staff Uses For | Manager Uses For |
|-------|---------------|-----------------|
| `Shift` | Viewing assigned shifts | Creating/editing/deleting shifts |
| `Timesheet` | Submitting/viewing own hours | Approving/rejecting all timesheets |
| `AppUser` | Own profile only | All staff profiles (name resolution, staff picker) |
| `Message` | Reading notifications | (Not actively used yet in manager UI) |
| `RosterTask` | Completing tasks | Creating/editing/reviewing tasks |
| `TaskCompletion` | Recording own completions | Viewing all completions, redo requests |
| `AppSettings` | Company name display | Company name / ABN / address display + edit |
| `ShiftAttendance` | Clock-in/out (server-timestamped) | Verified Attendance card, geofence verdicts |
| `DailyJobTemplate` / `DailyJobAssignment` | Complete/undo assigned jobs | Curate job library, assign per shift |
| `RosterLocation` | (workplace geofence for clock-in) | Create/edit work locations |
| `WageModels` (award/line/profile) | — (never exposed to staff) | Wage module (manager-only) |
| `ClockSession` | Live device-local clock timer | — |

---

## Shared Services

| Service | Staff Usage | Manager Usage |
|---------|-------------|---------------|
| `AuthService` | Login/logout/password | Same |
| `WorkerAPIClient` | Save availability, complete password change | Send notifications |
| `DeviceAuthService` | Biometric gate | Biometric gate |
| `CalendarService` | Add shifts to calendar | Not used |
| `FirebaseBootstrap` | Initialize Firebase | Same |
| `LocationService` | GPS fix for clock-in/out geofence | — |
| `NotificationService` | Register/sync FCM push token | Same |
| `ServerClock` | Server-time reference (clock-skew detection) | Same |
| `ShiftReminderScheduler` | Local shift-start / forgot-clock reminders | — |
| `ImageCompressor` | Downscale/compress task proof photos (≤2 MB) | Reads |
| `TaskPhotoCache` | Sandbox cache for task photos | Sandbox cache + 90-day review retention |

---

## Authentication: Shared Path, Different Destinations

Both roles go through the same authentication pipeline:

```swift
// In RootView.swift
switch authVM.state {
case .loading:
    // Splash screen
case .unauthenticated:
    LoginView()  // Same for both roles
case .authenticated:
    if let user = repo.currentUser {
        if user.role == .manager {
            ManagerMainView()  // Manager UI
        } else {
            MainTabView()      // Staff UI
        }
    }
}
```

The `AuthViewModel` doesn't know about roles — it just handles Firebase Auth state. The role check happens at the `RootView` level after `RosterRepository` loads the user document.

---

## Real-Time Synchronization

Both sides operate on **real-time Firestore listeners** (`onSnapshot`). This means:

1. When a manager publishes a shift, the staff member's roster view updates **instantly** (within seconds)
2. When staff submits hours, the manager's pending count updates **instantly**
3. When a manager approves a timesheet, the staff's history/roster updates **instantly**

There's no polling, no manual refresh needed (though pull-to-refresh is available as a fallback via `refreshFromServer()`).

---

## Security & Access Control

### Firestore Rules (server-side)

While the app uses client-side role filtering, Firestore Security Rules on the server enforce
(authoritative copy: `docs/reference/firestore.rules.deployed`):
- Staff read/write is scoped to their own records (`staffId`/`recipientId`/`completedBy ==
  request.auth.uid`), with per-field whitelists — e.g. staff can never write approval fields
  (`approvedBy`/`approvedAt`/`managerNotes`), and a self-reported absence must carry zero hours.
- Managers can read all documents and write shift/timesheet approval fields (`isManager()` =
  role `manager` + status `active`).
- All writes require authentication (`request.auth != null`).
- `shift_attendance` is an **append-only audit trail**: staff can never delete records, and
  `clockInAt`/`clockOutAt` may only ever be written as `request.time`
  (`FieldValue.serverTimestamp()`), so a manipulated device clock can't forge them.
- The `wages` collection is **unreadable by staff** — earnings data is manager-only.

> Access control is role-based, not tenant-based: the app is intentionally single-tenant
> (one business per Firebase project), so there is no `businessId` partition key yet. See the
> tenancy note in `docs/agents.md`.

### Client-Side Enforcement

The `RosterRepository` adds role-based query filters:
- Staff listeners include `.whereField("staffId", isEqualTo: uid)`
- Manager listeners have no staffId filter (gets all documents)

### Worker API Authorization

All Worker API calls include a Firebase ID token. The Cloudflare Worker verifies the token and checks the user's role in Firestore before executing operations.

---

## Shared Design System

Both sides use the same `Theme` and `DesignSystem/Components/`:
- Same color palette (brand indigo, accent green)
- Same typography scale
- Same card styles, buttons, status pills
- Same haptic feedback patterns

The manager side uses the same `Color(hex: 0x4F46E5)` as `Theme.brand` for consistency.

---

## Communication Between Roles

### Manager → Staff Communication Channels

1. **Shifts** — Publishing a shift is how the manager tells staff "you work this day"
2. **Timesheet status** — Approving/rejecting communicates hours decision
3. **Messages** — Direct messages in the `messages` collection (sent via web/API, displayed in staff's NotificationsSheet)
4. **Push notifications** — (When enabled) Real-time alerts for shift changes, approvals, rejections

### Staff → Manager Communication Channels

1. **Timesheets** — Submitting hours for review
2. **Absence reports** — Reporting inability to work a shift
3. **Availability** — Setting when they can/can't work (manager sees this when planning roster)
4. **Task completions** — Completing assigned tasks with photo proof

---

## Extending the System

### Adding a Feature for Both Roles

If a feature needs to show different content per role:

1. Create separate views: `Features/{Feature}/` (staff) and `Features/Manager/{Feature}/` (manager)
2. Both views read from the same `RosterRepository`
3. The repository already provides role-filtered data — no extra work needed
4. Add navigation entry points to `MainTabView` (staff) and `ManagerMainView` (manager)

### Adding a Shared Feature

If a feature is identical for both roles:
1. Create it in `Features/Shared/` or `Features/{Feature}/`
2. Reference it from both `MainTabView` and `ManagerMainView`
3. Use `repo.currentUser?.role` if minor role-based UI differences are needed

### Adding Manager-Only Data

1. Add new Firestore collection/query in `RosterRepository.start(uid:)` under the manager branch
2. Add property to `RosterRepository`
3. Create views in `Features/Manager/{Feature}/`
4. Wire up in `ManagerMainView`
