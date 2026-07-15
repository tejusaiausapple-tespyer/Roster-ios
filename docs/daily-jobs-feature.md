# Daily Jobs — Manager & Staff

Completely separate from the Tasks feature. Managers keep a **permanent
library of reusable job templates** and assign a selection of them to one
staff member's specific shift. Staff see assignments for the full shift date;
templates never expire.

## Data model (Firestore)

- `daily_job_templates` (`Models/DailyJob.swift`): title, active, createdAt,
  createdBy. Manager-only (read + write). Never auto-deleted.
- `daily_job_assignments`: doc ID `{shiftId}_{templateId}` (idempotent
  re-assign). Fields: shiftId, staffId, templateId, title (snapshot), date
  (shift date, for windowed listeners), assignedAt/By, completed,
  completedAt/By. Staff read their own and may only toggle the
  `completed/completedAt/completedBy` fields; managers do everything else.
- **Deploy needed:** rules (`docs/reference/firestore.rules.deployed`) and the
  `(staffId, date)` composite index on `daily_job_assignments`
  (`docs/reference/firestore.indexes.json`). See `docs/reference/README.md`
  for how deploys actually work.

## Manager workflow

- Dashboard → Today's Roster → tap a staff shift row →
  `DailyJobAssignSheet`: job library with multi-select checkboxes, search,
  inline **+ Add Job** (creates a permanent template), Save.
- Saving syncs the shift's assignments: newly ticked jobs are created,
  unticked ones removed, already-assigned ones keep their completion state.
- The same sheet shows live progress (pending/completed + completion time),
  and the roster row shows a live "Jobs n/m" chip. Firestore listeners push
  updates — no refresh.

## Staff workflow

- The Home bell badge counts unread messages **plus pending daily jobs**.
- The notifications panel shows a Daily Jobs card for today's shift:
  each job has Complete / Undo, toggleable until end of day (Adelaide TZ).
- Jobs disappear from the panel after the shift **date** rolls over
  (`DailyJobAssignment.isVisibleToStaff`); history stays in Firestore for the
  manager.

## Key files

- `Models/DailyJob.swift`, `Services/RosterRepository.swift` (listeners +
  addDailyJobTemplate / setDailyJobs / setDailyJobCompleted / dailyJobs(forShift:))
- Manager: `Features/Manager/Dashboard/DailyJobAssignSheet.swift` (+ roster
  row wiring in `ManagerDashboardView.swift`)
- Staff: `Features/Home/NotificationsSheet.swift`, bell badge in `HomeView.swift`
- Tests: `RosterraTests/DailyJobTests.swift`

## Future (per plan, not built yet)

- Edit/delete templates, push notifications on assignment (needs Worker
  event), assignment history view per staff member.
