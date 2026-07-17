# Production Roadmap — Progress Tracker

> Handoff document. Any agent/developer continuing this work: read `docs/agents.md`
> first, then this file. One branch per milestone; merge to `main` only after
> Sura builds & verifies on device (see `docs/smoke-test.md`) and the test suite
> passes (`xcodebuild test -project Rosterra.xcodeproj -scheme Rosterra`).
> Run `xcodegen generate` after pulling if Swift files were added/removed.

**Repo:** https://github.com/tejusaiausapple-tespyer/Roster-ios.git
**Web/PWA repo (reference):** https://github.com/tejusaiausapple-tespyer/Roster.git
**Deployed Firestore rules (authoritative):** `docs/reference/firestore.rules.deployed`
**Test suite status:** 149 passed / 0 failed (last run 2026-07-10, iPhone 17 Pro sim)

---

## Milestone status

- [x] **Marketing site responsiveness fixes** (branch `marketing-site-responsive-fixes`, completed 2026-07-13)
  - Constrained mockup dimensions on desktop (`max-height: 540px`/`460px`), tablet (`38vh`), and mobile (`32vh`).
  - Stacked showcase and download grids, scaled typographic headings, section paddings, and card gutters.
  - Enabled flex wrapping for Hero tags and footer links to prevent horizontal scroll.
  - Linked HTML pages to `style.css` and verified Vite production build succeeds.
- [x] **M0 — Version control & safety net** (merged: `main`)
  - git init, baseline commit, tag `baseline-v1.0.0`, remote pushed
  - `docs/smoke-test.md` created (17-step regression gate)
- [x] **M1 — Documentation corrections** (merged)
  - Collection names, tab bar, password rules, listener diagram, auth flow,
    duplicate headings, stale status lists all fixed
- [x] **M2 — Testing foundation** (merged)
  - `RosterraTests` target + scheme in `project.yml`; 58 tests
    (BusinessRules, HoursMetrics, Calendar/Format, model parsing)
- [x] **M3 — Security & access gates** (merged; verified on device)
  - `App/AppRoute.swift`: pure routing; managers now pass forced-password +
    Face ID gates (15 truth-table tests)
  - PasskeyStore password → biometric-gated Keychain item (+ legacy migration)
  - `temporaryPassword` cleared on background
  - Firestore rules reviewed against deployed copy (see reference file)
- [x] **M4 — Data integrity** (merged to main 2026-07-05, device-verified;
      merge d45a344 also includes the iOS 26 glass hit-testing fix and the
      owner-requested manager-portal updates: locations manager + company
      details w/ ABN/ACN/+61/structured address, role dropdown, break default
      0, dashboard lifecycle statuses, quick actions, nav-bar Save pill,
      profile header pills)
  - [x] CRITICAL: `saveShift` writes `shiftStartAt` + `submittableAfter`
        Timestamps (deployed rules require them for staff timesheet writes;
        Worker crons need them for reminders)
  - [x] HoursMetrics submittedAt fallback (year/month undercount fixed)
  - [x] Role-aware `refreshFromServer` for managers
  - [x] `deleteShift` cascades to attached timesheets (batched)
  - [x] ChangeEmailView split writes (staff `emailChangeRequired` write was
        rules-denied and sank the whole update)
  - [x] Manager notifications: `timesheet-approved`, `timesheet-rejected`,
        `roster-published` (hyphenated names from Worker registry)
  - [x] `markMessagesRead` batched
- [ ] **M5 — Error handling & user feedback** — ✅ CODE COMPLETE on branch
      `milestone-5-error-handling`, ⏳ awaiting Sura's device verification
  - [x] All `// Handle error` silent catches in ManagerRosterView replaced
        with Toast feedback (copy/publish/delete/move/copy/bulk-delete, with
        partial-failure counts on bulk delete)
  - [x] In-flight guard + "Copying…" label on Copy Last Week (double-tap
        previously duplicated the whole week); empty-week info toast
  - [x] ManagerTimesheetDetailSheet: approve failure → toast, sheet stays
        open; reject failure → inline banner inside the reason sheet (typed
        input preserved)
  - [x] repo.loadError rendered as a Banner on the Manager Dashboard
  - [x] roster-published notification on single-shift publish (parity)
- [ ] **Branch `wages-and-shift-flow`** (owner request 2026-07-05) — ✅ CODE
      COMPLETE, ⏳ awaiting Sura's device verification (96 tests pass)
  - [x] Timesheets editable until approved: `BusinessRules.canSubmitHours`
        now allows pending/draft edits (matches deployed rules); SubmitHours
        sheet shows "Update hours"; Roster swipe shows "Edit"
  - [x] Break surfaced when confirming shifts: manager timesheet row shows
        "Xm break / no break" (detail sheet already did); break is deducted
        in `calcWorkedHours`
  - [x] Clock in/out: `Models/ClockSession.swift` + repo session methods +
        `Features/Home/ClockInCard.swift` (Start Shift → Start/End Break →
        End Shift → Submit hours). DEVICE-LOCAL by necessity: deployed rules
        block staff timesheet writes before `submittableAfter`, so the
        session persists in UserDefaults (survives relaunch) and seeds
        SubmitHoursSheet (start/end/break, rounded to 5m, clamped 0–90);
        session cleared on successful submit. No break taken → 0m, submit
        fine. FUTURE: to show live clock-ins to managers, rules must allow
        staff `draft` timesheet creates from `shiftStartAt` (owner action).
  - [x] Wages module: `Models/WageModels.swift` (Xero-AU-style awards w/
        classifications, earnings lines w/ rate types + super/tax exemption,
        per-staff profiles) in manager-only `wages` collection; Wage tab UI
        (`Features/Manager/Wage/ManagerWageView.swift`, also reachable from
        Account); nothing seeded — managers create awards/lines manually
  - [x] Earnings-line assignment in Staff tab (`StaffWageAssignmentSheet`) —
        manager-only, stored in `wages`, never on user docs
  - [x] Superannuation % per staff: `AppUser.superRate` + editable row in
        the manager staff detail sheet ("Pay (manager only)" section)
  - [x] FIX (2026-07-05, Sura's iPad repro): **Publish Week failed on device**
        — `publishAllDrafts` queried `date range + status == draft`, which
        needs a `(status, date)` composite index that is NOT deployed (only
        `(staffId, status, date)` exists) → FAILED_PRECONDITION. The PWA
        worked because it batch-updates ids already in memory. Now queries by
        date only, filters drafts client-side, chunks batches at 500, and
        writes PWA-parity fields on publish (`publishedAt`, `updatedAt`,
        backfilled `shiftStartAt`/`submittableAfter`). Single-shift publish
        moved to new `repo.publishShift` (same fields; previously a full
        `saveShift` rewrite without `publishedAt`).
  - [x] FEATURE (2026-07-05, owner request): **Availability week locking** —
        Publish Week now offers "Publish Only" / "Publish & Lock
        Availability"; ⋯ menu locks/unlocks the displayed week. Lock state:
        `settings/availabilityLocks` `weeks` map (manager-write under
        existing rules; no rules change). Staff AvailabilityView shows
        locked weeks read-only ("Locked by your manager" banner); recurring
        saves/resets skip locked weeks. SERVER enforcement added to the
        Worker's `/api/staff/availability` (web repo, branch
        `availability-week-lock` in ~/Desktop/Roster-old — Sura must deploy
        the Worker + PWA for enforcement to go live). PWA got the same
        publish modal, toolbar lock pill, and staff-page lockout.
  - [x] FIX (2026-07-05, Sura's repro): **Resubmit after rejection showed no
        form** — every Resubmit entry point (History swipe, Home card) routes
        via `router.pendingSubmitShiftId` to RosterView's `.task(id:)`, but
        that task and the submit/absence sheets were attached to the stack's
        root content, which SwiftUI marks disappeared while HistoryView is
        pushed — so nothing fired and staff were stranded on History. Moved
        both `.task(id:)` deep-link handlers and the SubmitHours/ReportAbsence
        sheets onto the NavigationStack itself; the sheet now presents even
        over History. VERIFY: reject a timesheet, then resubmit from both the
        History swipe action and the Home card.
  - [x] UX (2026-07-05): iPad sidebar — Sura preferred the ORIGINAL plain
        list, so the grouped/branded redesign was reverted (both platforms);
        kept: profile footer pinned at the sidebar bottom that opens the
        Account tab (highlighted when selected). Also fixed: "Approved on"
        raw ISO string (M7 item), TaskCompletionDetailSheet wrong
        "Completed By" (M7 item).
- [ ] **M6 — Domain robustness** (PARTIALLY DONE via `manager-portal-updates`
      branch, 2026-07-05, per Sura's product answers)
  - [x] Shift editor: seeded locations REMOVED → manager-created locations
        (suburb + AU state dropdown + auto capital city), stored on
        `settings/locations` (`Models/RosterLocation.swift`, repo listener +
        `addLocation`)
  - [x] Role free-text → dropdown: "Console Operator" / "Junior Attendee"
        (legacy values still shown when editing old shifts)
  - [x] Default break = No break (0 min, was 30)
  - [x] Staff filters by `fullName` → filter by staff id (ManagerRosterView,
        ManagerTimesheetsView; 2026-07-06, branch milestone-6-domain-robustness)
  - [x] Super rate & default hourly rate centralized in BusinessRules
        (defaultSuperRatePercent = 12 — AU SG since 2025-07-01, was 11.25%;
        defaultHourlyRate = 25). Reports & Roster wage cards now use
        per-staff `superRate` when set. NOTE for Sura: weekly super figures
        will read higher than before (12% vs 11.25%).
  - [x] SetupRequiredView now prints the live bundle id (was stale
        com.sura.roster.staff)
  - [ ] Remove unused ManagerBlockedView — still awaiting Sura's OK
        (open decision below)
- [ ] **M7 — UI/UX correctness** — ✅ CODE COMPLETE on branch
      `milestone-7-uiux-correctness` (2026-07-06), ⏳ awaiting Sura's device
      verification
  - [x] Dashboard Today's Roster: chronological by start time; in-progress
        shift highlighted (brand bar/pill; placeholder until Staff Portal
        "Start Shift" tracking exists); "Clocked In" → "Submitted"
  - [x] Dashboard Quick Actions wired: New Shift → editor sheet, Staff
        Directory → staff view, New Task → placeholder
  - [x] Roster agenda: selected day snaps into the displayed week, so Add
        Shift defaults to the viewed week's first day (or today if current
        week), and a tapped day is respected
  - [x] Dashboard/Tasks date formatters → RosterFormat business-TZ helpers
        (time/dateFull/hhmm Date overloads; 2026-07-06, branch
        milestone-7-uiux-correctness). Also fixed: shift editor SAVE path
        serialized HH:mm device-local, and task editor dueTime round-trip.
  - [x] TaskCompletionDetailSheet "Completed By" resolves `completedBy`
  - [x] ManagerTimesheetDetailSheet "Approved on" ISO string (fixed 07-05)
  - [x] TasksView week-strip dots now only mark this user's tasks (07-06)
  - [x] Shift editor default times Calendar.current → RosterCalendar (07-06)
  - [x] Staff Home header redesign (Sura feedback 07-06): company name → bold,
        truncating toolbar pill (top-left); greeting becomes prominent in-page
        heading; bell badge overlaps the icon (~1/3) instead of floating
  - [x] Daily Jobs notification panel UX (Sura feedback 07-06): rows keep
        position on complete (no reorder jump; Complete↔Undo in place), taller
        rows, more spacing, independent hidden-indicator scroll in the medium
        detent
  - [x] Staff shift card button label reflects state — "Update hours" for a
        pending (still-editable) timesheet, was stuck on "Submit hours" and
        read as a failed submission (Sura feedback 07-06)
- [ ] **M8 — Performance** — ✅ CODE COMPLETE on branch
      `milestone-8-performance` (2026-07-06), ⏳ awaiting Sura's device
      verification
  - [x] `RosterCalendar.calendar` cached as `static let` (was a computed var
        rebuilding a Calendar on every date operation)
  - [x] `usersById` + `timesheetsByShiftId` indexes on RosterRepository,
        maintained via didSet; new `user(id:)` helper. All 19 manager-view
        `allUsers.first(where: id ==)` scans → O(1) (was O(n²) per list).
        `timesheet(forShift:)` uses the index, keeping first-wins + the
        legacy id fallback.
  - [x] `pendingFirstSnapshot` now includes shifts + timesheets, so isLoading
        stays true until the roster actually arrives (was flashing an empty
        roster before role-listener data streamed in)
- [ ] **M9 — Accessibility & design consistency** — ✅ CODE COMPLETE on branch
      `milestone-9-accessibility` (2026-07-06), ⏳ awaiting Sura's device
      verification (needs a real VoiceOver + Dynamic Type pass on device)
  - [x] Dynamic Type: content-text `.system(size:)` → scalable semantic fonts
        — Tasks + ManagerTasks miniStats (title3/caption2), Login titles
        (title3 rounded), ManagerAvailability grid micro-labels (caption2/
        caption; the day-cell already has minimumScaleFactor so it stays
        overflow-safe). SF Symbol icon sizes (48/44/34/26pt) left fixed —
        icons don't need text scaling.
  - [x] Reduce Motion: LoginView error shake gated behind
        `accessibilityReduceMotion` (6 call sites → one `triggerShake()`
        helper; haptic + error banner still convey failure). NOTE: the
        "orbs/border sweep" the roadmap mentioned were already removed in a
        prior login redesign — only the shake remained.
  - [x] VoiceOver: labels/hints on icon-only controls — password show/hide
        toggle, New Task button, dashboard roster row (hints it opens Daily
        Jobs). Bell already labelled.
  - DEFERRED: exhaustive VoiceOver audit of every screen is device work best
    done with VoiceOver actually running — flagged for Sura's verification.
    Tiny fixed badges in size-constrained chrome (bell count, calendar count
    dots) intentionally left fixed to avoid layout breakage at accessibility
    sizes.
- [ ] **`audit-remediation` branch** — quality/bug-fix pass (2026-07-08), ⏳ awaiting Sura's device verification
  - [x] One-sheet-per-view navigation: `HeroCard` rename, TZ polish, logging
  - [x] O(1) shift+attendance indexes, best-effort writes, safe `roleOptions`
  - [x] BUG FIX: Manager Availability tab not reflecting staff saves — two root causes:
        (1) `WorkerAPIClient.saveAvailability` discarded the Worker response (`_ = try await post(...)`)
        so any 200 with non-JSON body (e.g. SPA HTML fallback if endpoint unreachable)
        was treated as success; now validates `{ ok: true }` and throws a user-visible
        error if the Worker does not confirm the write.
        (2) `ManagerAvailabilityView` only accessed `repo.allUsers` inside the `GeometryReader`
        closure, which executes during layout — outside SwiftUI's `@Observable` tracking
        window — so the view never re-rendered when staff saved. Added
        `.onChange(of: repo.allUsers) { _, _ in }` to anchor the dependency
        outside the closure and trigger re-renders on any user availability change.
  - VERIFY: staff saves availability for next week → manager navigates to that
    week in Manager Portal → data appears without navigating away/back. Check
    that saving availability shows a real error toast (not false success) if the
    network is down.
  - [x] Version management system (2026-07-10):
        `Models/AppRelease.swift` — `AppRelease` struct + `ReleaseHistory` enum
        (static registry, newest-first). `Features/Shared/AppVersionHistoryView.swift`
        — App Store-style changelog pushed from both portals.
        Account → About → Version row is now a `NavigationLink` (both portals);
        removed the local `appVersion` computed var from both Account views.
        `project.yml` remains the single source of truth for version/build numbers;
        to cut a new release: prepend to `ReleaseHistory.all`, bump
        `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml`, run
        `xcodegen generate`. No Firestore, no extra dependencies.
  - VERIFY: tap Version in Staff Account → About → changelog opens; tap Version
    in Manager Account → About → same view. "v1.0.0" shown in the row label.
    Long-press the commit hash row → "Copy commit hash" context menu appears.
- [ ] **M10 — CI** (NOT STARTED)
  - GitHub Actions: xcodegen → build → test on PRs (web repo has a CI to copy
    patterns from). pbxproj is gitignored so no drift check needed.
- [ ] **M11 — Manager Tasks / Tenure / Wage tabs** (Tasks + Tenure built;
      Tasks awaiting owner verification; Tenure MVP shipped 2026-07-16 —
      exports / charts still deferred)
  - Tasks: manager tab (list/editor/review + redo flow), staff upgrades
    (assignment, priority, due time, tick-only tasks, notes), photo lifecycle
    (<=2 MB uploads, sandbox-only storage, staff week-end sweep, manager
    14-day cloud backstop + 90-day local retention). New proof photos store
    `gs://` Storage references under `task_photos/{uid}/...` so manager review
    uses Storage rules instead of public download-token URLs. See
    docs/tasks-feature.md.
  - **Task assign push** (branch `fix/task-assign-push-notification`, 2026-07-16):
    `saveTask` fires Worker `message-task` on create / assignee change so
    assigned staff get a lock-screen "New task" banner. ⏳ device verify.
  - Multi-photo proof (2026-07-06): up to 4 photos per completion,
    staffPhotoUrls array + legacy staffPhotoUrl mirror for PWA parity.
  - **Daily Jobs** (2026-07-06, owner plan; docs/daily-jobs-feature.md):
    separate from Tasks — permanent daily_job_templates library, per-shift
    daily_job_assignments ({shiftId}_{templateId} ids), manager assigns from
    dashboard roster rows w/ live Jobs n/m progress, staff Complete/Undo via
    bell panel until shift end. Rules + (staffId,date) index in
    docs/reference/ — Sura deployed 2026-07-06 (firestore + storage; storage
    needed the cross-service IAM grant, see docs/reference/README.md).
    2026-07-16: Job library trailing delete (confirm → remove template;
    existing shift assignments keep snapshotted history).
  - DEPLOYED 2026-07-06: Firebase Storage rules for task proof/reference photo
    paths (`docs/reference/storage.rules`) are live in project `roster-8a270`.
  - VERIFY after Storage rules deploy: staff completes a photo-required task;
    Firebase Storage shows the object under `task_photos/{staffUid}/...`;
    `task_completions/{taskId}_{date}.staffPhotoUrl` starts with `gs://`;
    manager opens the completion photo, then taps "Reviewed — delete photo
    from cloud" and the Storage object is removed.
  - FUTURE (owner request 2026-07-05): **Payslip feature** — staff-visible
    payslips rendering the business details from `settings/app` (company
    name, address, ABN, contact — already captured via Account → Company
    Details). Slot alongside the Wage tab work.
- [x] **M12 — App Store & push** (paid team `GS2KGPX9P8` wired 2026-07-15;
      see docs/WHEN_DEVELOPER_ACCOUNT_READY.md, now a closure note)
  - [x] NSCameraUsageDescription added to Info.plist (2026-07-06)
  - [x] Push wired end-to-end: APNs → FCM (`MessagingDelegate`) → Firestore `fcmToken`
  - [x] Associated Domains entitlement live; `apple-app-site-association` TEAMID
        placeholder bug found + fixed (was still live in production)
  - [x] App Store packaging blockers cleared 2026-07-16 (build 2): opaque
        AppIcon-1024, NSPhotoLibraryUsageDescription,
        NSCalendarsWriteOnlyAccessUsageDescription, PrivacyInfo collected-data
        types, employer-managed account deletion UX, About legal links.
        See docs/APP_STORE_SUBMISSION.md for ASC notes + device QA checklist.
  - [ ] Passkey keep-or-remove decision still open — entitlement/domain
        association work is done, but `PasskeyManager.register()` has no UI
        entry point anywhere in the app, so registration can't be triggered yet
  - [ ] Trademark / domain / App Store name conflict checks still open
        (docs/BRANDING.md). Deploy PWA `/terms` + confirm support@ mailbox
        before first upload.

---

## M4 device-verification checklist (do this before merging M4)

1. Manager: create a NEW shift ending a few minutes ago, publish → staff:
   shift shows "Awaiting submission", Submit Hours SUCCEEDS. In Firebase
   console, shift doc has `shiftStartAt` + `submittableAfter` timestamps.
2. Manager pull-to-refresh on Roster/Timesheets works.
3. Delete a shift that has a pending timesheet → timesheet doc gone from
   console; Dashboard pending count drops.
4. (If PWA push enabled) approve a timesheet natively → PWA staff gets push.
5. Staff Home/History hour tiles sane.

Then: `git checkout main && git merge --no-ff milestone-4-data-integrity && git push`

---

## Payroll module (owner request 2026-07-09) — ✅ CODE COMPLETE on branch
`audit-remediation`, ⏳ awaiting Sura's device verification (rules deployed 2026-07-10)

- New `payslips` collection (doc id `{periodStart}_{staffId}`; corrections `_c{n}`).
  Weekly DRAFT payslips auto-generate idempotently (client-side, first manager
  session on/after Monday, last completed week) from APPROVED timesheets +
  wage assignments; manual generate button per period too. NOTHING is ever
  sent/published automatically.
- Workflow: Draft → Under Review → Approved → Submitted (→ Archived); staff
  see a payslip ONLY after Submit. Submitted payslips are immutable in-app —
  "Issue corrected copy" archives the original and creates a new draft.
- Manager Portal → Payroll tab (iPad/Mac sidebar): period navigator, status +
  gross/PAYG/super/net overview tiles, staff payslip list, recent periods;
  full payslip editor (hours buckets × editable rates, allowances, PAYG/
  deductions/salary sacrifice, super %, live totals) + live A4 AU-style PDF
  (`PayslipPDFService` renders preview AND export — always identical).
- Staff → Account → Payslips: grouped history, PDF view/share/print/save.
- Wage assignment sheet gained employment type, age group, rate override,
  effective date, active toggle (`StaffWageProfile` extended; legacy docs
  parse as active).
- Audit: every generate/edit/status-change/download appended to the payslip's
  `audit[]` + best-effort `auditLogs` entries.
- Tests: +15 (`PayrollTests`) — calculator totals (super excludes overtime +
  exempt rows), weekend bucketing, status flags, Firestore round-trips.
- **DEVICE VERIFICATION**: (1) ~~Sura deploys the payslips rules block~~ ✅
  deployed 2026-07-10 (`payslips` + `emailChangeRequired` in
  `firestore.rules.deployed`). (2) Manager: open Payroll, generate drafts
  for a week with approved timesheets, edit hours/rates, preview PDF, approve,
  submit. (3) Staff account: payslip appears ONLY after submit; PDF opens,
  share/save works. (4) Confirm staff sees nothing pre-submit (drafts) and
  cannot read another staff member's payslips.

## Manager Portal UI restore (owner request 2026-07-10) — ✅ on `audit-remediation`

- Wage & Payroll tabs back on native `List` + `.insetGrouped` (a Cursor session
  had rewritten them as ScrollView cards with fixed-height nested lists —
  clipped rows, broken Dynamic Type). Kept from that session: the
  `TitlePillCollapseReporter` height-constrained-GeometryReader fix and all
  wage/classification features.
- Swipe-to-delete on Wage Awards, Classification Levels, Other pay items and
  draft/under-review payslips — every delete goes through a **centered alert**
  (Cancel/Delete); nothing deletes unconfirmed. Unused `ManagerInsetSection`
  removed.
- Staff tab grid: top/bottom gradient fade while scrolling
  (`ScrollFadeHints` gained `showsChevrons: false` mode) — geometry-driven,
  device-size independent.
- Device-feedback round (2026-07-10): (a) killed the ~100pt dead space above
  the first card in Wage/Payroll — the loose zero-height
  `TitlePillCollapseReporter` row formed an implicit List section (44pt min
  row height + section spacing); it now sits in its own `Section` with
  `.listSectionSpacing(0)` + `defaultMinListRowHeight 1`. (b) Console age-rate
  seed template removed entirely (Wage button, editor shortcut, repo
  `ensureConsoleAward`/`addConsoleClassificationLevels`,
  `consoleTemplateClassifications/Lines`, template test) — owner decision:
  managers create awards/levels manually. (c) Staff search field pinned
  (`.navigationBarDrawer(displayMode: .always)`) so pull-to-refresh no longer
  drags it down over the filter chips.
- Device-feedback round 2 (2026-07-10): Classification dropdown in the Staff
  wage-assignment sheet now lists levels in the exact order of the Wage →
  Classification Levels list — both use the new shared
  `ClassificationDisplayOrder` (numeric-aware level code, title fallback);
  the Wage list's previous comparator was also invalid (unstable order) and
  is fixed by the same helper. +3 ordering tests.
- Round 3 (2026-07-10): (a) Payslip PDF redesigned — monochrome ink on white
  (no colour fills/tinted text; logo is the only colour), letter-spaced
  section labels, roomier tables, bordered net-pay panel, wrapped values
  measured so rows never collide. (b) Manager-assigned **Employee ID**
  (letters+numbers, stored uppercase in `users.employeeId`): editable in the
  Staff detail sheet, shown on the staff Account page, manager payslip sheet
  and the PDF; snapshotted onto payslips at generation
  (`payslips.employeeId`) with live fallback for older slips
  (`repo.displayEmployeeId(for:)`). Replaces the truncated-uid "Employee ID".
- Round 4 (2026-07-10): Staff Account → Payslips month filter with cache-first
  loading. Redesigned to use an inline glassmorphic capsule pill aligned top-left
  with a spring-animated scale + opacity dropdown containing a year scroll wheel
  and a month grid selector (no chevrons, sheet, or layout jumps). Tap outside to close. The
  staff full-history payslips **listener is removed** — the screen fetches one
  month at a time via `staffPayslips(monthKey:)`: session memory → Firestore
  persistent disk cache (`source: .cache`, zero reads, offline-capable) →
  server (only never-downloaded months, the current month once per session,
  or pull-to-refresh). The month query keeps the rule-proven equality pair
  (staffId + status-in) and bounds by documentID (`{periodStart}_` prefix) —
  no composite index; a fallback to the old equality-only query guards
  against FAILED_PRECONDITION. "Downloaded months" tracked per-uid in
  UserDefaults so empty months don't re-hit the server. Account tab's payslip
  count badge removed (it required full history). +4 month-key tests.
- **DEVICE VERIFICATION**: (1) Wage tab: both segments start right under the
  segmented control (no dead space); no Console age-rate button anywhere;
  swipe an award / classification level / pay item → centered dialog; Cancel
  keeps it, Delete removes with toast. (2) Payroll: "Pay period" card sits
  just below the nav bar; swipe a draft payslip → centered confirm.
  (3) Staff: search field always visible; pull-to-refresh spins without
  dragging the search field; grid fades under top/bottom edges; iPhone +
  iPad. (4) Title pill still collapses on scroll in Wage/Payroll/Staff.
  (5) Staff Payslips Month Picker: tap Account → Payslips. Verify a single
  left-aligned glass pill ("July 2026") under the back button. Tap it; confirm the
  floating year wheel + month grid picker scales out smoothly below without layout
  jumps. Selecting a month closes it, updates query, and loads payslips. Tapping
  outside closes the picker. Check dark/light mode and safe areas.

## Live cost/wage-profile parity fix (2026-07-17) — branch `fix/live-cost-wage-profile-resolution`

- **Root cause**: Roster's live "Gross $" cost chip, the Reports screen, and
  the Timesheet detail sheet each independently did `user.hourlyRate ?? 25.0`
  — completely bypassing the `StaffWageProfile`/`WageAward`/`EarningsLine`
  model that payroll generation (`buildDraftPayslip`) already used. Found
  while cross-checking parity against the PWA, which had just been migrated
  to the same wage model (see `docs/PWA-IOS-PARITY-AND-DISCREPANCY-REPORT.md`
  §2.2 in the sibling `Roster` repo root).
- **Fix**: new `StaffWageProfile.loadedRate(profile:award:earningsLines:
  shiftDateKey:)` (`WageModels.swift`) reuses the exact same
  `resolvedHourlyRate`/`resolvedWeekendRate` precedence as payroll, plus a new
  `RosterCalendar.isWeekend(dateKey:)` day-of-week check payroll doesn't need
  (it buckets hours by day itself). New `RosterRepository.liveHourlyRate(
  forStaffId:shiftDateKey:)` wraps it with the existing `hourlyRate ?? 25.0`
  fallback chain, unchanged as a last resort. Wired into all four call sites:
  `ManagerRosterView.grossWages`/`.superannuation`, `ManagerReportsView.rate`
  (and fixed `perStaff`'s cost calc, which previously multiplied total
  scheduled hours by a single flat rate instead of costing each shift at its
  own rate — a separate latent bug in the same area), and
  `ManagerTimesheetDetailSheet.rate`. No auto casual-loading multiplier
  anywhere, matching the existing payroll model exactly.
- +7 unit tests in `PayrollTests.swift` (`testIsWeekendDetectsSaturdayAndSunday`,
  `testLoadedRate*`). All 183 tests pass.
- **Also fixed while in the area**: `docs/agents.md` had it backwards on which
  Firestore rules file is authoritative — corrected, and re-synced
  `docs/reference/firestore.rules.deployed` from the actual live file (see the
  new note in `docs/agents.md` "Behaviors To Know").
- **DEVICE VERIFICATION**: (1) Assign a staff member a wage profile with a
  classification level that has both a Mon–Fri and a weekend rate (Wage →
  Classification Levels, or Staff → wage assignment sheet). (2) Roster tab:
  confirm the "Gross $" chip changes when you add a weekend shift for that
  staff member vs a weekday one, using the classification's rates (not their
  bare `hourlyRate`, if different). (3) Reports tab: same staff member's
  per-staff "Cost" column should reflect the correct weekday/weekend split if
  they have shifts on both. (4) Timesheets tab → open that staff member's
  timesheet detail: rostered/actual cost should use the same resolved rate,
  not a flat guess. (5) For a staff member with NO wage profile assigned at
  all, confirm all three screens still show a sane number (falls back to
  `hourlyRate`, then $25 default) — this path must not regress.

## Owner (Sura) actions pending — Firebase console

0. ~~REQUIRED for Payroll: deploy the `payslips` rules block~~ ✅ 2026-07-10
1. ~~RECOMMENDED: add `'emailChangeRequired'` to the `isValidSelfUserUpdate`~~ ✅ 2026-07-10
2. RECOMMENDED: tighten `task_completions` rules so staff can't overwrite each
   other's completions (require create-only, or `resource.data.completedBy ==
   request.auth.uid` on update). *(Already in `firestore.rules.deployed` — verify on device.)*
3. ~~When Firestore rules are redeployed, update `firestore.rules.deployed`~~ ✅ 2026-07-10

## Open decisions (answers needed before the milestone that uses them)

- M6: super rate set to 12% (AU SG) as BusinessRules fallback on 2026-07-06 —
  Sura to confirm, and decide if constants should move to Firestore settings.
- M6: real shift locations/departments (replace Melbourne/Sydney/Brisbane)?
- M6: OK to delete unused ManagerBlockedView?
- M12: keep passkeys (wire registration + Associated Domains) or remove?

## Working conventions (from the full roadmap, Phase 3 conversation)

- One branch per milestone: `milestone-N-<slug>`; merge --no-ff after Sura
  verifies on device; push branch before handoff.
- Never weaken tests to make them pass; add tests with each behavior change.
- `.claude/settings.local.json` is tracked and mutates every session — stash
  it around checkouts (`git stash push .claude/settings.local.json`), or
  finally untrack it (Sura previously deferred this).
- Update `docs/agents.md` when adding files/behaviors (project rule).
- Commit messages end with the Co-Authored-By Claude trailer (see git log).
