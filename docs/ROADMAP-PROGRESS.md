# Production Roadmap — Progress Tracker

> Handoff document. Any agent/developer continuing this work: read `docs/agents.md`
> first, then this file. One branch per milestone; merge to `main` only after
> Sura builds & verifies on device (see `docs/smoke-test.md`) and the test suite
> passes (`xcodebuild test -project RosterStaff.xcodeproj -scheme RosterStaff`).
> Run `xcodegen generate` after pulling if Swift files were added/removed.

**Repo:** https://github.com/tejusaiausapple-tespyer/Roster-ios.git
**Web/PWA repo (reference):** https://github.com/tejusaiausapple-tespyer/Roster.git
**Deployed Firestore rules (authoritative):** `docs/reference/firestore.rules.deployed`
**Test suite status:** 96 passed / 0 failed (last run 2026-07-05, iPhone 17 Pro sim)

---

## Milestone status

- [x] **M0 — Version control & safety net** (merged: `main`)
  - git init, baseline commit, tag `baseline-v1.0.0`, remote pushed
  - `docs/smoke-test.md` created (17-step regression gate)
- [x] **M1 — Documentation corrections** (merged)
  - Collection names, tab bar, password rules, listener diagram, auth flow,
    duplicate headings, stale status lists all fixed
- [x] **M2 — Testing foundation** (merged)
  - `RosterStaffTests` target + scheme in `project.yml`; 58 tests
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
  - [ ] Staff filters by `fullName` → filter by staff id (ManagerRosterView,
        ManagerTimesheetsView)
  - [ ] Centralize super rate (11.25% — CHECK with Sura: AU SG is 12% from
        2025-07-01) and default hourly rate ($25) in BusinessRules/AppSettings
  - [ ] Fix stale bundle-id string in SetupRequiredView; remove unused
        ManagerBlockedView (ask first); run `xcodegen generate` after removal
- [ ] **M7 — UI/UX correctness** (PARTIALLY DONE via `manager-portal-updates`)
  - [x] Dashboard Today's Roster: chronological by start time; in-progress
        shift highlighted (brand bar/pill; placeholder until Staff Portal
        "Start Shift" tracking exists); "Clocked In" → "Submitted"
  - [x] Dashboard Quick Actions wired: New Shift → editor sheet, Staff
        Directory → staff view, New Task → placeholder
  - [x] Roster agenda: selected day snaps into the displayed week, so Add
        Shift defaults to the viewed week's first day (or today if current
        week), and a tapped day is respected
  - [ ] Dashboard/Tasks date formatters → RosterCalendar/RosterFormat
        (currently device-local TZ)
  - [ ] TaskCompletionDetailSheet shows wrong "Completed By"
        (uses current user, should resolve `completedBy`)
  - ManagerTimesheetDetailSheet "Approved on" prints raw ISO string
  - TasksView week-strip dots mark any staff's completions
  - Shift editor default times use Calendar.current → RosterCalendar
- [ ] **M8 — Performance** (NOT STARTED)
  - Cache `RosterCalendar.calendar` (recomputed per access)
  - Dictionary lookups (usersById, timesheetsByShiftId) in manager views
  - `pendingFirstSnapshot` doesn't include role-listener labels → isLoading
    clears before shifts/timesheets arrive
- [ ] **M9 — Accessibility & design consistency** (NOT STARTED)
  - Fixed font sizes → Dynamic Type (LoginView, TasksView, Dashboard,
    ManagerAvailability cells); Reduce Motion on LoginView orbs/border sweep;
    VoiceOver pass
- [ ] **M10 — CI** (NOT STARTED)
  - GitHub Actions: xcodegen → build → test on PRs (web repo has a CI to copy
    patterns from). pbxproj is gitignored so no drift check needed.
- [ ] **M11 — Manager Tasks / Tenure / Wage tabs** (NOT STARTED; placeholders)
  - FUTURE (owner request 2026-07-05): **Payslip feature** — staff-visible
    payslips rendering the business details from `settings/app` (company
    name, address, ABN, contact — already captured via Account → Company
    Details). Slot alongside the Wage tab work.
- [ ] **M12 — App Store & push** (BLOCKED on paid Apple Developer account;
      checklist in docs/WHEN_DEVELOPER_ACCOUNT_READY.md)
  - ALSO: verify NSCameraUsageDescription in Info.plist (TasksView uses the
    camera — string appears to be MISSING; can be fixed any time, crash/
    rejection risk on device camera use)
  - Passkey keep-or-remove decision (registration UI never wired)

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

## Owner (Sura) actions pending — Firebase console

1. RECOMMENDED: add `'emailChangeRequired'` to the `isValidSelfUserUpdate`
   allowlist in Firestore rules (restores manager email-request flow fully).
2. RECOMMENDED: tighten `task_completions` rules so staff can't overwrite each
   other's completions (require create-only, or `resource.data.completedBy ==
   request.auth.uid` on update).
3. When either is done, update `docs/reference/firestore.rules.deployed`.

## Open decisions (answers needed before the milestone that uses them)

- M6: super rate 11.25% → 12%? Source constants from Firestore settings?
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
