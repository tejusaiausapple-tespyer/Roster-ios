# Staff Side Documentation

> Complete technical reference for the staff-facing features of RosterStaff.

---

## Overview

The staff side is the primary user experience. Staff members (employees) use this app to:
- View their rostered shifts
- Submit worked hours (timesheets) after shifts end
- Report absences
- Manage their weekly availability
- Complete assigned tasks with photo evidence
- View messages from their manager
- Manage their account/profile

---

## Entry Point & Navigation

### Tab Bar (`Features/Shell/MainTabView.swift`)

Staff users see a 5-tab interface:

| Tab | View | Icon | Purpose |
|-----|------|------|---------|
| Home | `HomeView` | `house` | Dashboard with upcoming shifts, action items, hours summary |
| Roster | `RosterView` | `calendar` | Full week-by-week shift schedule |
| Tasks | `TasksView` | `list.bullet.clipboard` | Daily/weekly task completion with photos |
| Availability | `AvailabilityView` | `calendar.badge.clock` | Weekly availability management |
| Account | `AccountView` | `person.crop.circle` | Profile, settings, logout |

> **History is not a tab.** `HistoryView` is pushed from the Roster tab via the
> "View Shift History" card (and deep links route `history` paths to the Roster tab).

---

## Feature Details

### 1. Home (`Features/Home/HomeView.swift`)

**What it shows:**
- Greeting with staff first name
- Company name from AppSettings
- "Action Needed" carousel — shifts that require timesheet submission or have been rejected
- Next upcoming shift card
- Hours summary (approved this week/month)
- Unread messages count with notification bell

**Key interactions:**
- Tap notification bell → `NotificationsSheet` (list of active messages)
- Tap "Action Needed" shift → opens `SubmitHoursSheet`
- Pull to refresh → calls `repo.refreshFromServer()`

**Data sources:**
- `repo.shifts` filtered by upcoming dates
- `repo.timesheets` for status checking
- `repo.messages` for unread count
- `BusinessRules.needsStaffAction()` for action-needed logic

---

### 2. Roster (`Features/Roster/RosterView.swift`)

**What it shows:**
- `WeekSelector` at top for navigating weeks (Monday–Sunday)
- Day-by-day list of shifts using `ShiftCard` components
- Action-needed carousel at top (shifts needing submission)
- Empty state when no shifts for a day

**Key interactions:**
- Swipe shift card left → "Submit Hours" or "Report Absence" actions (context-dependent)
- Tap shift card → expands details or triggers action sheet
- "Add to Calendar" action → `CalendarService.addShift()`
- Week navigation arrows / "Today" button
- Pull to refresh

**Business logic:**
- Shifts visible within `BusinessRules.staffShiftDateRange()` (28 days back, 56 days forward)
- `BusinessRules.displayStatus()` determines the status pill shown
- `BusinessRules.canSubmitHours()` / `canReportAbsence()` gate the swipe actions
- Locked weeks (too far in the past) show a lock indicator

**Related components:**
- `ShiftCard` (`Features/Shared/ShiftCard.swift`) — reusable shift display card with hero/standard/compact variants
- `SubmitHoursSheet` (`Features/Shared/SubmitHoursSheet.swift`) — time picker form for worked hours
- `ReportAbsenceSheet` (`Features/Shared/ReportAbsenceSheet.swift`) — absence reporting with optional reason

---

### 3. Submit Hours (`Features/Shared/SubmitHoursSheet.swift`)

**Flow:**
1. Pre-fills with rostered start/end times
2. Staff adjusts actual start/end times using time pickers
3. Staff sets actual break minutes (0–90, step 5)
4. Worked hours auto-calculated: `(end - start - break)`
5. Optional staff notes field
6. Submit → creates/updates timesheet in Firestore with status `pending`

**Resubmission:**
- If timesheet was rejected, staff can resubmit with corrected times
- Uses `repo.resubmitTimesheet()` which sets status back to `pending`

**Validation:**
- Start time must be before end time
- Worked hours must be > 0
- Break minutes clamped to valid range

---

### 4. Report Absence (`Features/Shared/ReportAbsenceSheet.swift`)

**Flow:**
1. Staff selects a shift they'll be absent from
2. Optional reason text field
3. Submit → creates timesheet with status `absent_reported`
4. Can be undone with `repo.undoAbsenceReport()`

**Rules:**
- Only available BEFORE shift becomes submittable (before shift end time)
- Not available if an approved timesheet already exists
- `BusinessRules.canReportAbsence()` controls visibility

---

### 5. Tasks (`Features/Tasks/TasksView.swift`)

**What it shows:**
- Today's applicable tasks (filtered by frequency: daily/weekly/once)
- Each task shows: title, description, completion status, photo requirement
- Completed tasks show checkmark with timestamp and staff name

**Key interactions:**
- Tap "Complete" → marks task as completed in Firestore
- Camera button → opens `CameraPicker` for photo evidence
- Photo saved locally via `TaskPhotoCache` and URL stored in `task_completions`
- Tap completed task → `TaskCompletionDetailSheet` with full details and photo

**Task types:**
- `once` — appears only on the specific `date` field
- `daily` — appears every day
- `weekly` — appears on specified `dayOfWeek` values (1=Monday...7=Sunday)

**Data model:**
- `RosterTask` — the task definition (from `tasks` collection)
- `TaskCompletion` — completion record (in `task_completions` collection, ID format: `{taskId}_{date}`)

---

### 6. History (`Features/History/HistoryView.swift`)

**Entry point:** pushed from the Roster tab's "View Shift History" card (not a tab bar item).

**What it shows:**
- All past timesheets grouped by month
- Filter by status (all, pending, approved, rejected, absent)
- Filter by time period (all time, this month, last month, etc.)
- Search by shift location or notes

**Key interactions:**
- Tap a timesheet → shows full details inline
- Status pills show current state (pending, approved, rejected, absent)
- Shows rostered vs actual hours, break minutes, manager notes

**Data:**
- `repo.timesheets` — full list, filtered client-side
- Grouped using `RosterFormat.monthYear()` for section headers

---

### 7. Availability (`Features/Availability/AvailabilityView.swift`)

**What it shows:**
- Week-based view of staff's availability pattern
- Each day shows: available (yes/no), all-day or specific hours
- Navigation between weeks (-2 to +12 from current)
- Save/reset buttons

**Key interactions:**
- Tap a day → `DayEditSheet` with toggles for available/unavailable, all-day, time pickers
- Save → `WorkerAPIClient.saveAvailability()` (goes through Cloudflare Worker to Firestore)
- Reset → reverts to last saved state

**Data model:**
- `UserAvailability` with `[Weekday: DayAvailability]` dictionary
- Stored in user document under `weeklyAvailability` keyed by week start date (`yyyy-MM-dd`)
- `BusinessRules.availabilityMaxWeekOffset` (12) and `availabilityMinWeekOffset` (-2) control editable range

---

### 8. Account (`Features/Account/AccountView.swift`)

**What it shows:**
- Profile header (name, initials avatar, role, employment type)
- Personal details section (email, phone, DOB, address, emergency contact)
- Employment info (start date, member since, hourly rate — if available)
- App settings (biometric lock toggle, theme)
- Actions: Change Email, Change Password, Logout

**Key interactions:**
- Edit profile fields → `repo.updateProfile()` saves to Firestore
- Toggle biometric lock → enables/disables `DeviceAuthService`
- Change Password → navigates to `ChangePasswordView`
- Change Email → navigates to `ChangeEmailView`
- Logout → `AuthViewModel.signOut()`

---

## Authentication Flow (Staff Perspective)

```
App Launch
    │
    ├── Missing GoogleService-Info.plist → SetupRequiredView (developer setup screen)
    │
    ├── No auth → LoginView
    │       ├── Email + Password login
    │       │     (login rejects locked/inactive accounts with an error and signs out)
    │       ├── Passkey or biometric quick-login (if previously enabled;
    │       │     refused if last manual login was > 7 days ago)
    │       └── Forgot password → Firebase password reset email
    │
    └── Authenticated → RootView checks, in order:
            ├── role == .manager → ManagerMainView (skips the gates below — see audit)
            ├── mustChangePassword → ChangePasswordView (forced)
            ├── needsProfileCompletion (incl. profileUpdateRequired) → ProfileCompletionView
            ├── DeviceAuth enabled & not verified → DeviceAuthGateView
            └── All clear → MainTabView (staff tabs)

Mid-session: if the account becomes locked/inactive, RootView force-signs-out
with a message shown on the login screen. (`ManagerBlockedView` is legacy/unused.)
```

---

## Shared Components Used by Staff Views

| Component | File | Used In |
|-----------|------|---------|
| `ShiftCard` | `Features/Shared/ShiftCard.swift` | RosterView, HomeView |
| `SubmitHoursSheet` | `Features/Shared/SubmitHoursSheet.swift` | RosterView, HomeView |
| `ReportAbsenceSheet` | `Features/Shared/ReportAbsenceSheet.swift` | RosterView |
| `HoursMetrics` | `Features/Shared/HoursMetrics.swift` | HomeView (hours summary) |
| `ShareSheet` | `Features/Shared/ShareSheet.swift` | Calendar ICS sharing |
| `WeekSelector` | `DesignSystem/Components/WeekSelector.swift` | RosterView, AvailabilityView |
| `StatusPill` | `DesignSystem/Components/StatusPill.swift` | ShiftCard, HistoryView |
| `Toast` | `DesignSystem/Components/Toast.swift` | Most views (success/error feedback) |
| `EmptyStateView` | `DesignSystem/Components/EmptyStateView.swift` | All lists when empty |
| `Banner` | `DesignSystem/Components/Banner.swift` | RosterView (action needed) |
| `CameraPicker` | `DesignSystem/Components/CameraPicker.swift` | TasksView |

---

## Staff Data Access Pattern

Staff users can only:
- **Read** their own shifts (filtered by `staffId` in Firestore query)
- **Read** their own timesheets (filtered by `staffId`)
- **Read** their own messages (filtered by `recipientId`)
- **Read** all active tasks (tasks collection — shared across all staff)
- **Write** their own timesheets (submit/resubmit)
- **Write** their own task completions
- **Write** their own availability (via Worker API)
- **Write** their own profile updates

The `RosterRepository` enforces this by using `staffId == uid` filters in its Firestore listeners when the user role is `.staff`.

---

## Key Staff Business Rules Quick Reference

| Rule | Implementation |
|------|---------------|
| Can submit hours? | `BusinessRules.canSubmitHours(shift:timesheet:at:)` |
| Can report absence? | `BusinessRules.canReportAbsence(shift:timesheet:at:)` |
| Shift needs action? | `BusinessRules.needsStaffAction(shift:timesheet:at:)` |
| Display status | `BusinessRules.displayStatus(for:timesheet:at:)` |
| Week locked? | `BusinessRules.isWeekLockedForStaff(weekStartKey:at:)` |
| Shift visible? | Within `staffShiftDateRange` (28 days back, 56 forward) |
| Password valid? | `BusinessRules.passwordErrors(_:)` returns empty array |
