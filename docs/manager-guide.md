# Manager Side Documentation

> Complete technical reference for the manager-facing features of Rosterra.

---

## Overview

The manager side provides administrative capabilities for the business owner/manager. Managers can:
- View a real-time dashboard with today's metrics
- Create, edit, publish, and delete shifts for all staff
- Approve or reject staff timesheets
- View task completion logs
- Manage their own account

The manager UI is accessed when `AppUser.role == .manager` is detected after login.

---

## Entry Point & Navigation

### Tab Bar / Sidebar (`Features/Manager/Shell/ManagerMainView.swift`)

The manager interface is **adaptive**:
- **iPhone**: 5-tab `TabView` (Dashboard, Roster, Tasks, Timesheets, Account)
- **iPad/Mac**: `NavigationSplitView` with sidebar + detail

### Manager Tab Enum (`Features/Manager/Shell/ManagerNavigation.swift`)

```swift
enum ManagerTab: String, CaseIterable, Identifiable {
    case dashboard    // "Dashboard" - square.grid.2x2
    case roster       // "Roster" - calendar
    case timesheets   // "Timesheets" - clipboard
    case staff        // "Staff" - person.2 ✅ implemented
    case tasks        // "Tasks" - list.bullet.clipboard (placeholder)
    case availability // "Availability" - calendar.badge.clock ✅ implemented
    case reports      // "Reports" - chart.bar ✅ implemented
    case tenure       // "Tenure & Hours" - rosette (placeholder)
    case wage         // "Wage" - dollarsign.circle (placeholder)
    case account      // "Account" - gear
}
```

**Currently implemented tabs:** Dashboard, Roster, Timesheets, Staff, Availability, Reports, Account
**Placeholder tabs:** Tasks, Tenure & Hours, Wage

> **iPhone** shows 5 tabs (Dashboard, Roster, Tasks, Timesheets, Account); **Staff, Availability, and Reports are reached from the Account tab's "Management" section** (above Notifications), pushed with `embedInNavigationStack: false` to avoid a nested navigation bar. **iPad/Mac** shows all tabs in the sidebar.

---

## Feature Details

### 1. Dashboard (`Features/Manager/Dashboard/ManagerDashboardView.swift`)

**What it shows:**
- Company header (SURA INVESTMENTS PTY LTD + Manager Portal branding)
- Today's date
- 4 metric cards:
  - Active Staff / Total today's shifts
  - Hours Scheduled (sum of today's `scheduledHours`)
  - Tasks Completed / Total today's tasks
  - Pending Timesheets count
- Quick Actions row (New Shift, New Task, Staff Directory — buttons, not yet wired)
- Today's Roster Status — list of today's shifts with staff name, time, clocked-in status
- Today's Task Logs — recent task completions with timestamps and photo verification indicator

**Data sources:**
- `repo.shifts` filtered by `todayKey`
- `repo.timesheets` for pending count and clocked-in status
- `repo.tasks` filtered by frequency rules for today
- `repo.taskCompletions` filtered by today's date
- `repo.allUsers` for resolving staff names

**Key computed properties:**
- `todaysShifts` — shifts where `date == todayKey`
- `activeStaffCount` — shifts that have a matching timesheet
- `totalScheduledHours` — sum of today's `scheduledHours`
- `pendingTimesheetsCount` — timesheets with `status == .pending`
- `completedTasksCount` — tasks completed today
- `recentCompletions` — today's completions sorted by time (newest first)

**Layout:**
- iPhone: single column VStack
- iPad: HStack with two columns (quick actions + roster on left, task logs on right)

---

### 2. Roster Management (`Features/Manager/Roster/ManagerRosterView.swift`)

The roster is **adaptive and width-driven** (not size-class-only), so it behaves correctly across iPad fullscreen, portrait, Split View, Slide Over, and resized Mac windows. It adopts the 2026 **Liquid Glass** design on the navigation layer (iOS/iPadOS/macOS 26+) with an automatic `.ultraThinMaterial` fallback on iOS 17–25.

**Two layout modes (`RosterLayoutMode`, chosen by measured container width):**
- **Agenda** (`width < 720`, and always on iPhone) — the single-day list + `WeekSelector`. This is the compact/iPhone design and is intentionally preserved.
- **Week grid** (`width >= 720`, iPad/Mac) — a 7-column week scheduler.

**Week grid details:**
- Centered at `Theme.maxContentWidth` (1400) so wide Mac windows don't stretch.
- **7 day columns always fit the width** — `colWidth = available / 7`. There is **no horizontal scrolling**; only vertical scrolling within the week when a day has many shifts.
- Pinned day-header row (fixed height so the greedy vertical dividers don't stretch it) showing weekday, day number (Adelaide timezone via `RosterCalendar`), today highlight, shift count, and a per-day glass "+".
- Shift cards are the **content layer** and stay solid (no glass) for legibility.

**Glass control bar (top), reflows by width (two rows under 980pt):**
- Week navigator pill — `‹ [relative week label] ›`. The center shows **"This week" / "Next week" / "Last week" / "In N weeks" / "N weeks ago"** (reflects `weekOffset`); when off the current week it turns brand-colored with a return arrow and taps back to this week.
- Date range label (exact dates, Adelaide timezone).
- **Delete chip** (red trash icon) — see below. Positioned to the left of the Staff menu.
- Staff filter chip + Status filter chip (compact fixed labels with an active-state dot).
- ⋯ More menu — Copy Last Week, Publish Week (N).
- **Add shift** (`.glassProminent`).

**Add-shift default date:**
- General "Add shift" button uses `defaultNewShiftDateKey` — today if today is in the viewed week, otherwise that week's **start date (Monday)**.
- Per-day "+" (header and empty-column "Add") passes its own exact date.

**Drag & drop (grid):**
- Only **draft** shifts are draggable (`.draggableIf(isDraft, …)`). Dropping on another day offers **Move** or **Copy** via a confirmation dialog.
- **Published shifts are locked** — they cannot be dragged/moved/copied (enforced on the card and in `handleShiftDrop`). Adding new shifts is always allowed.

**Bulk delete (the red trash chip):**
- Options: **All staff (N)** or a specific staff member's shifts. Operates on `allWeekShifts` (ignores the active view filters) with a destructive confirmation dialog.
- **Visibility (`canBulkDelete`):** upcoming weeks → shown; current week → shown only if it has **no published shifts**; past weeks → hidden (completed); also hidden when the week is empty.

**Per-shift interactions:**
- Tap a card → `ManagerShiftEditorSheet` (edit). Context menu: Edit, Publish (drafts only), Delete.
- Agenda mode keeps swipe actions (Delete / Edit / Publish) and a floating add FAB.

**Shift Editor (`Features/Manager/Roster/ManagerShiftEditorSheet.swift`):**
- Staff picker (all active staff from `repo.allUsers`)
- Date picker (seeded from `defaultDateKey`)
- Start/End time pickers
- Break minutes stepper
- Location text field
- Department text field
- Notes text field
- Status selector (draft/published)
- Auto-calculates `scheduledHours`
- Create mode: calls `repo.saveShift(...)` to create; Edit mode: updates existing
- NOTE: default 09:00/17:00 times are seeded with device-local `Calendar.current`; switch to `RosterCalendar.calendar` if strictly Adelaide-consistent default times are ever required (date is unaffected).

**Bottom metrics bar** (glass, via `.safeAreaInset(.bottom)`): hours, staff count, drafts, gross wages, total inc. super — as compact chips that reflow (single row → horizontal scroll fallback for very large Dynamic Type).

**Shift lifecycle (manager perspective):**
1. **Draft** — created but not visible to staff (draggable)
2. **Published** — visible to assigned staff member (locked from drag)
3. **Completed** — shift has an approved timesheet
4. **Cancelled** — shift was cancelled (not deleted)

**Operations:**
- `repo.saveShift(...)` — create or update
- `repo.deleteShift(id:)` — permanent delete (also used by bulk delete, iterated per shift)
- `repo.publishAllDrafts(from:to:)` — batch publish all drafts in the week

**Design-system glass helpers** (in `DesignSystem/Theme.swift`): `glassSurface(in:tint:interactive:)`, `glassCapsule(...)`, `glassProminentSurface(in:tint:)` — gated by `#if compiler(>=6.2)` + `if #available(iOS 26.0, *)` with material fallback.

---

### 3. Timesheets (`Features/Manager/Timesheets/ManagerTimesheetsView.swift`)

The Timesheets tab is **week-based and single full-width** (no split screen), mirroring the Roster tab's week navigation, with 2026 **Liquid Glass** on the navigation layer (iOS 17–25 fall back to `.ultraThinMaterial`).

**Structure:**
- **Week selector** (glass) — `‹ [This week / Last week / N weeks ago] ›` + date range. Bounds: back to the shift window (`shiftWeekOffsetBounds.min`), forward capped at the current week (`max = 0`, since there are no future timesheets). Off-week, the center label is brand-colored and taps back to this week.
- **Filter row (no scrolling):** minimal status pills **Pending (N) / Approved (N) / Rejected (N)** (counts for the selected week; selected = solid brand, unselected = clean card pill — no frosted glass), **centered on their own line** below the week-nav row. The **Staff** filter chip sits on the week-nav row.
- **Adaptive card grid** — timesheets for the selected week flow into a `LazyVGrid(.adaptive(minimum: 300, maximum: 480))`: 1 column on iPhone, more as width grows. Centered at `Theme.maxContentWidth`. No two-pane split.
- **Bottom summary bar** (fixed footer — scrolling ends above it) — sheets count, hours worked, pending count for the week, in darker text.
- Tapping a card opens `ManagerTimesheetDetailSheet` **as a sheet on every device**.

**Week → timesheet mapping:** the week's shifts are collected from `repo.shifts` (already loaded for the manager window); timesheets are matched by `shiftId`. So the tab shows timesheets for shifts worked in the selected week.

**Timesheet card (content layer — solid):** staff initials/name, shift date (`RosterFormat.date`), status pill, hours worked with a warning + rostered-vs-actual when they mismatch, and the submitted date.

**Detail (`Features/Manager/Timesheets/ManagerTimesheetDetailSheet.swift`):**
- Staff header, shift comparison (rostered vs actual), financial variance (hours × `hourlyRate`), staff notes, manager comments editor, status history.
- **Approve / Reject** actions are **pinned in a frosted-glass bar at the bottom** (via `.safeAreaInset`) so they're always visible without scrolling; content scrolls beneath. Buttons use Liquid Glass (`.glassProminentSurface` accent / `.glassSurface` warning-tinted). Close stays in the top toolbar.
- Has an `isEmbedded` flag (hides the "Close" toolbar button when embedded) — currently always presented as a sheet, so Close shows.
- Approve → `repo.approveTimesheet(id:managerNotes:)`; Reject → `repo.rejectTimesheet(id:reason:managerNotes:)` via a reason sheet.

**Approval flow:**
1. Staff submits timesheet → status becomes `pending`
2. Manager reviews in Timesheets tab
3. Manager approves → status becomes `approved`, stores `approvedBy` + `approvedAt`
4. Manager rejects → status becomes `rejected`, stores `rejectedReason`
5. Staff sees rejection, can resubmit → goes back to `pending`

**Data note:** the manager timesheets listener is windowed to `managerTimesheetWindowDaysBack` (90 days) — see `docs/agents.md`.

**Operations:**
- `repo.approveTimesheet(id:managerNotes:)` — sets status to approved with manager UID and timestamp
- `repo.rejectTimesheet(id:reason:managerNotes:)` — sets status to rejected with reason

---

### 4. Account (`Features/Manager/Shell/ManagerAccountView.swift`)

**What it shows:**
- Same as staff AccountView but styled for manager
- Profile information
- Change password
- Logout

---

## Manager Data Access Pattern

Manager users have broader access than staff:
- **Read ALL** shifts (no staffId filter — sees entire roster)
- **Read ALL** timesheets (sees all staff submissions)
- **Read ALL** users (for staff directory and name resolution)
- **Read ALL** tasks and task completions
- **Write** shifts (create, edit, delete, publish)
- **Write** timesheets (approve, reject)
- **Write** own profile

The `RosterRepository` detects manager role and removes `staffId` filters from Firestore queries, loading the complete dataset.

---

## Manager-Specific Files

| File | Purpose |
|------|---------|
| `Features/Manager/Dashboard/ManagerDashboardView.swift` | Dashboard with metrics and activity logs |
| `Features/Manager/Roster/ManagerRosterView.swift` | Full roster management with shift CRUD |
| `Features/Manager/Roster/ManagerShiftEditorSheet.swift` | Create/edit shift form |
| `Features/Manager/Timesheets/ManagerTimesheetsView.swift` | Timesheet list with filtering |
| `Features/Manager/Timesheets/ManagerTimesheetDetailSheet.swift` | Timesheet detail + approve/reject |
| `Features/Manager/Shell/ManagerMainView.swift` | Adaptive tab/sidebar navigation |
| `Features/Manager/Shell/ManagerNavigation.swift` | `ManagerTab` enum with all tab definitions |
| `Features/Manager/Shell/ManagerPlaceholderView.swift` | Placeholder for unimplemented tabs |
| `Features/Manager/Shell/ManagerAccountView.swift` | Manager account/settings view |

---

## Additional Implemented Manager Tabs

### 5. Staff (`Features/Manager/Staff/ManagerStaffView.swift`)
Staff directory with **editing**. Adaptive card grid, `.searchable`, segmented status filters. Tapping a card opens `ManagerStaffDetailSheet` (a Form). **Editing is per-field**: each field (Full name, Phone, Employment type) is locked with a **pencil** to unlock and a **checkmark** to save *just that field* → `repo.updateStaffFields(staffId:, [key: value])` writes only the changed key (+ `updatedAt`). No bulk "save all". Requires Firestore rules allowing manager writes to user docs.

**Email (request-and-self-confirm):** the manager does **not** set the email directly (it's a sign-in credential). The Email section has an **"Ask {name} to change their email"** button → `repo.requestStaffEmailChange(staffId:)` sets `emailChangeRequired = true`. The **staff** then sees a banner in their Account tab (`AccountView.emailRequestSection`) → "Change email" opens the existing `ChangeEmailView`, which reauthenticates and calls `verifyBeforeUpdateEmail` (Firebase sends a verification link; the email changes only after they click it). Completing it clears `emailChangeRequired`. The manager can also "Cancel request" (`repo.cancelStaffEmailChange`).

**"Require new address on next login"** — `repo.requestStaffAddressUpdate(...)` clears the address and sets `profileUpdateRequired`; `RootView` routes the staff to `ProfileCompletionView` (forces a new address, has a Sign out button). Status/rate/dates shown read-only.

### 6. Availability (`Features/Manager/Availability/ManagerAvailabilityView.swift`)
Week-based view of every staff member's availability. Week selector (bounds −2…+12 weeks, matching staff availability). Reads `user.weeklyAvailability[weekKey] ?? user.availability ?? .defaultAvailability`. Wide (iPad/Mac ≥720pt): a staff × 7-day **matrix** with per-day "available" counts in the header. Narrow (iPhone): per-staff cards with a 7-day strip. Cells: green "All day" / times, red "Off". Bottom summary: staff count + best-covered day.

### 7. Reports (`Features/Manager/Reports/ManagerReportsView.swift`)
Weekly analytics computed from loaded shifts + timesheets. Week selector. Metric cards: Scheduled hours, Worked (approved) hours, Labour cost (gross × 1.1125 super), Shifts, Staff rostered, Pending. Timesheet status breakdown (approved/pending/rejected). Per-staff table (scheduled vs approved-worked hours, cost = scheduled × `hourlyRate`, default $25). Bottom summary: scheduled/worked hours + total cost.

---

## Planned Manager Features (Not Yet Implemented)

These tabs still show `ManagerPlaceholderView`:

| Tab | Intended Purpose |
|-----|-----------------|
| Tasks | Task management — create/edit/delete tasks, view completion reports |
| Tenure & Hours | Staff tenure tracking, total hours per employee |
| Wage | Wage calculation based on hours × rate, exportable payroll data |

Also not yet wired: the Dashboard "Quick Actions" buttons (New Shift / New Task / Staff Directory are visual only). Staff record editing IS implemented — see §5 above.

---

## Manager Notification Capabilities

The manager can trigger notifications to staff via the Worker API:

```swift
WorkerAPIClient.shared.sendNotification(
    event: "roster-published",    // or "timesheet-approved", "timesheet-rejected"
    shiftIds: ["shift1", "shift2"],
    timesheetId: "ts123"
)
```

Event names are hyphenated and must match the Worker's `NOTIFICATION_EVENTS`
registry. `RosterRepository` sends `timesheet-approved` / `timesheet-rejected`
on approval decisions and `roster-published` from `publishAllDrafts`.

This calls `POST /api/send-notification` on the Cloudflare Worker, which handles push delivery (when enabled).

---

## Differences from Staff Side

| Aspect | Staff | Manager |
|--------|-------|---------|
| Shift visibility | Own shifts only | All staff shifts |
| Timesheet access | Own timesheets only | All timesheets |
| User list | Not available | All users (`repo.allUsers`) |
| Shift editing | Cannot edit shifts | Full CRUD |
| Timesheet editing | Submit/resubmit own | Approve/reject any |
| Navigation | 5-tab TabView | 5-tab / sidebar (adaptive) |
| Dashboard | Personal upcoming shifts | Business-wide metrics |
| Tasks | Complete tasks | View completions (manage planned) |
