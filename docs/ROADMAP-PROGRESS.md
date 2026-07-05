# Production Roadmap — Progress Tracker

> Handoff document. Any agent/developer continuing this work: read `docs/agents.md`
> first, then this file. One branch per milestone; merge to `main` only after
> Sura builds & verifies on device (see `docs/smoke-test.md`) and the test suite
> passes (`xcodebuild test -project RosterStaff.xcodeproj -scheme RosterStaff`).
> Run `xcodegen generate` after pulling if Swift files were added/removed.

**Repo:** https://github.com/tejusaiausapple-tespyer/Roster-ios.git
**Web/PWA repo (reference):** https://github.com/tejusaiausapple-tespyer/Roster.git
**Deployed Firestore rules (authoritative):** `docs/reference/firestore.rules.deployed`
**Test suite status:** 74 passed / 0 failed (last run 2026-07-05, iPhone 17 Pro sim)

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
- [ ] **M4 — Data integrity** — ✅ CODE COMPLETE on branch
      `milestone-4-data-integrity` (commit ef1c2a6), ⏳ AWAITING Sura's device
      verification, THEN merge to main. Verify steps are in the checklist below.
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
- [ ] **M5 — Error handling & user feedback** (NOT STARTED — next up)
  - Replace all `// Handle error` silent catches in ManagerRosterView
    (copyLastWeek, publish, delete, move/copy) with Toast feedback
  - In-flight guard on copyLastWeek (double-tap duplicates the week!)
  - ManagerTimesheetDetailSheet approve/reject: surface errors, keep sheet open
  - Render `repo.loadError` somewhere for managers (Banner on Dashboard)
  - Also: send `roster-published` on single-shift publish (publishSingleShift
    in ManagerRosterView) — parity gap noted in M4
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
