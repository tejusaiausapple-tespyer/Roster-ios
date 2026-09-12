# Mac and iPad redesign — PWA feature parity

Reviewed 9 September 2026. Scope: native Mac Catalyst and iPad redesign; iPhone appearance remains outside this phase. Reference checkout: `/Users/sura/Desktop/Roster/Roster PWA`.

This is a source-based feature inventory, not a claim that every PWA file has been read or every workflow tested. All manager and staff page entry points were inspected for navigation, controls, imports, and action handlers. Roster orchestration, drag helpers, drag tests, native drag/copy handlers, and selected reports/messages handlers received deeper inspection. No production writes or PWA changes were made.

## Roster requirements accepted from the user

- Preserve draggable cards. Dropping a draft on another day offers **Move shift**, **Copy shift**, and **Cancel**, with source and destination dates visible before committing.
- Move preserves the original shift identity; copy creates a new draft and leaves the source unchanged. Retain staff, hours, break, location, department, and notes. Generate date-dependent timestamps through the existing repository.
- **Only draft cards are draggable. Published cards are locked in every week**, including future weeks. Completed and cancelled shifts are not draggable. This lock concerns drag/move/copy; it does not silently remove existing explicit manager editing workflows.
- Copy last week offers **All staff** or **Selected staff**, with a searchable multiple-selection list and a preview of destination week, staff, shift counts, duplicates, and conflicts. Selection is explicit, not silently inferred from a display filter.
- Copy previous-week source shifts into new drafts, including published source shifts. This batch template operation does not move or unlock its source cards. Exclude cancelled shifts and never overwrite existing published destination shifts.
- Retain Week, Day, and Staff views. The initial concept's staff-row grid is an additional design direction, not approval to remove the existing week-card workflow.
- Preserve staff/status filters, week navigation, per-day creation, availability feedback, timesheet status, hours, wage/super forecast, missing-rate warnings, publishing, availability locking, and master-sheet workflows where applicable.

## Source findings and discrepancies

| Behavior | PWA source | Native source | Redesign decision |
|---|---|---|---|
| Drag permission | `src/lib/utils.ts:624–653`: manager, week view; blocks published shifts only in current week | `MacManagerRosterView.swift:524`: same current-week exception, additionally excludes cancelled; iPad `ManagerRosterView.swift:1589` requires draft at drop | Use the user's stricter draft-only rule across Mac/iPad |
| Move/copy chooser | `RosterPage.tsx:279–345`, modal around line 469 | Mac drop sheet and separate move/copy handlers | Preserve explicit chooser on drop |
| Collision handling | Drop handlers reject same-staff overlapping shifts; same-day drop ignored | Mac overlap helper and checks before move/copy | Preserve, including validation immediately before save |
| Copy last week | `RosterPage.tsx:253`: all non-cancelled previous-week shifts; does not read staff filter or selected staff | Mac `copyLastWeek` line 650 also all staff; iPad line 1321 also all staff | Add explicit all/selected-staff flow |
| Duplicate handling | PWA compares staff/date/start/end and ignores cancelled destination records | Mac compares staff/date/start/end including cancelled records; iPad uses its own copy key | Specify a consistent duplicate/conflict policy and report skipped rows before implementation |
| Publishing | Publishes all drafts in displayed week, independent of staff/status display filters | Separate native publishing flows | Make scope visible in confirmation |
| Availability lock | Publish Only vs Publish & Lock; independent week unlock action | Present in native flows | Keep separate from published-card drag lock; unlocking availability must not unlock published cards |

The PWA test `roster-drag.test.ts` explicitly expects future published cards to be draggable. That expectation conflicts with the new user requirement. Do not copy that test unchanged as the native acceptance standard. Tests were read, not executed during this review.

Recheck the live source status at drag start, drop, and final commit. If another manager publishes while the chooser is open, cancel the operation with a clear message. A cached drag payload is not permission. Prevent double submission and report partial batch-copy failures accurately; retries must skip successful copies.

## Tab-by-tab feature inventory

The source column is relative to the PWA checkout. These are preservation requirements for further native comparison, not assertions of verified native equivalence.

| Tab | PWA source | Behaviors to carry into native design review |
|---|---|---|
| Manager Dashboard | `src/pages/manager/Dashboard.tsx` | Weekly hours, today's roster, pending timesheets, actionable summary links, notifications setup |
| Roster | `src/pages/manager/RosterPage.tsx`, `src/components/roster/` | Week/day/staff views, filters, creation/edit/delete, availability feedback, drag chooser, previous-week copy, publish/availability lock, wage forecast, master-sheet upload/download |
| Timesheets | `src/pages/manager/TimesheetsPage.tsx` | Weekly staff/status filters, missing submissions route, detail review, approve/reject with notes, edit-and-approve, approved-hour editing, bulk approval, absence confirmation/undo, PDF export |
| Staff | `src/pages/manager/StaffPage.tsx` and imported staff components | Search/status filtering, creation and profile editing, detail view, temporary password reset, account lock/unlock, deactivation, placeholder handling; keep destructive actions distinct |
| Availability | `src/pages/manager/AvailabilityPage.tsx` | Weekly staff availability matrix, staff search, date navigation, availability states and time ranges |
| Reports | `src/pages/manager/ReportsPage.tsx` | Weekly/monthly/yearly periods, staff/status filters, approved/pending hours, staff charts and detail rows, Excel/CSV/PDF export using the chosen scope |
| Tenure & Hours | `src/pages/manager/TenureSummary.tsx` | Search, sortable staff summaries, tenure/hours detail, charts, Excel/PDF export |
| Wage | `src/pages/manager/WagePage.tsx` | Awards, classifications, earnings/pay items, ordinary/weekend rates, rate types, super/tax settings, legacy-rate presentation and guarded deletion |
| Messages | `src/pages/manager/MessagesPage.tsx` | Broadcast to all/selected staff, expiry settings, sent-date navigation, message editing, read/unread receipts. Do not collapse this into recurring Tasks or Daily Jobs |
| Settings | `src/pages/manager/SettingsPage.tsx` | Manager profile, company details, audit log, security/password, notifications, device authentication, app information; data-clearing is not a routine redesign action |
| Staff Home | `src/pages/staff/StaffHome.tsx` | Current/upcoming shifts, approved-hour summaries, notifications/read state, calendar export |
| Staff Roster | `src/pages/staff/StaffRoster.tsx` and staff shift/modal components | Week navigation, actionable shifts, submit/resubmit hours, absence/undo eligibility, deep links to a selected submission, calendar integration |
| Staff History | `src/pages/staff/StaffHistory.tsx` | Period/status filters, historical hours and status, links back to relevant work |
| Staff Availability | `src/pages/staff/StaffAvailability.tsx` | Per-day availability/time ranges, week locks, save, reset this week/following weeks |
| Staff Account | `src/pages/staff/StaffAccount.tsx` | Profile/employment details, password, device authentication, notifications, account-deletion request, sign-out |

The inspected PWA router (`src/App.tsx`) has no dedicated Tasks or Payroll page route. Native Tasks, Daily Jobs, verified attendance, and payslip/payroll functionality must still be retained from the native implementation; PWA parity alone is not the complete product specification. Wage reporting/PDF exports are not equivalent to a payroll review-and-publication workflow.

## Interaction design and acceptance checks

Mac: pointer drag with visible permitted targets, stable day headers, keyboard-accessible Move/Copy actions, and an anchored chooser. iPad: touch drag with readable preview and clear target feedback, plus an explicit Move/Copy action for accessibility and narrow windows. Preserve scroll position, week, filters, and selected staff through operations and resizing.

Before shipping the native roster slice, verify:

1. Draft drag → Move changes the date once and retains identity/details.
2. Draft drag → Copy creates one new draft, retaining the original.
3. Cancel/same-day drop leaves data unchanged.
4. Published cards cannot drag or commit a pending move/copy in past, current, or future weeks; cancelled/completed cards also cannot drag.
5. Conflicting destinations show an explanation and make no change.
6. Copy previous week works for all staff, one staff member, and multiple selected staff; no selection disables confirmation.
7. Repeated copy skips duplicates; cancelled sources are omitted; destination published shifts are preserved; partial failures can be retried without duplicating successes.
8. Publish Only and Publish & Lock both lock published cards; availability unlock never restores card dragging.
9. Width changes retain context across Week/Day/Staff views; keyboard, VoiceOver, and touch have equivalent actions.
10. iPhone behavior remains unchanged by the Mac/iPad visual implementation.

The initial interactive concept remains a visual sketch with sample data and does not yet implement this complete interaction contract. Native implementation should be evaluated against this document, not the sketch's limited controls.
