# Roster iOS — Reaudit 2026-09-30 (post-changes)

~175 Swift files re-read. No manager-gate / profile / version-gate regressions. Prior fixes intact.

## Regression & risk register

1. **Bulk approve bypasses 409 guard** (`RosterRepository.commitTimesheetApprovals` batch `updateData` without status check) — HIGH. Concurrent decision silently overwritten. Fix: transaction-check all or drop fast-path.
2. **Payroll generation drops PH/overtime** (`hoursBuckets` ordinary/weekend only; generation never sets `publicHolidayHours/overtimeHours`) — HIGH financial. Drafts understate loadings. Fix: bucket by shift metadata or PH flag.
3. **PH rate hardcoded 2.25x, no resolver** — MEDIUM. Award variance misprices.
4. **`BusinessRules.shiftStartDateTime` fail-open `Date()` on bad input** — MEDIUM. Unlock/submit gates open. Fail closed.
5. **Token never re-syncs after version unblock** (`NotificationService` + `RootView.setVersionAccessAllowed`) — MEDIUM. Device unreachable until relogin. Re-sync on unblock.
6. **Force-unwraps** (`shiftsById[id!]`, `existing!`, `explicit!`, `dept!`, `emergencyContact*!`, `selectedID!/selectedShiftID!`, `URL(...)!`, `components.url!`, `AppConfig apiBaseURL!/appStoreURL!`, `probeURL!`) — LOW today (guarded/literals), brittle. Replace with `guard let`.
7. **`LocationService` single-continuation race** — LOW (mitigated by `isStartingClockSession`). Queue or throw busy on concurrent `currentLocation()`.
8. **`deleteShift` attached-timesheet cache read** — LOW. Offline orphans inflate Dashboard pending. Use `.server`.
9. **Manager `refreshShiftWindow` full-org pull** — LOW now, scales poorly. Paginate/scope to week.
10. **Audit timestamps on device clock** (`nowISO`, PDF footer) — LOW forgeable. Use serverTimestamp where audit-critical.
11. **Entitlement `aps-environment production` for Debug** — LOW. Dev pushes fail. Split configs.
12. **LiveActivity device-TZ times** — LOW interstate confusion. Pin `RosterCalendar.timeZone`.
13. **Test gaps** — MEDIUM. No coverage for money-critical writes, OCC transactions, routing dead-ends, `ServerClock`, `PayslipPDF`, Worker locks, Mac hydrate, `ShiftFit`. Add at least PH/overtime buckets + approve guard + manager phone fail-closed tests.

Verified intact: `AppRoute` pure gate (setup→restoring→login→profileLoading→forcedPassword→profileCompletion→deviceGate→manager/staff), `AuthViewModel` fresh-login skips gate / restored re-requires / 2-min relock / `clearTokenOnLogout` before signOut, `AppRouter` deep-links (`surafoster://`, `sura-roster.com/auth/action?mode=resetPassword&oobCode`, `submit=/absent=/shiftAction`) + push mapping + phone fail-closed to `.account`, `RosterRepository` windows (-28/+56d shifts, 90d mgr timesheets, 5y staff, -26w payslips) + Mac 90d split + hydrate, clock `shift_attendance/{shiftId}` serverTimestamp + geofence enforced/lenient split, tasks ≤4 photos ≤2MB + `message-task` on assignee change, daily-jobs OCC (`dailyJobsVersion`, deterministic `{shiftId}_{templateId}`, 5-retry reorder), payroll auto-draft last Monday idempotent + `save/setStatus/delete/publish/regenerate/correct _cN` + month cache-first staff fetch, `WorkerAPIClient` 15s Bearer, `ServerClock` HEAD firestore + RTT, `ShiftReminderScheduler` 8 slots + hourly jobs, `DeviceAuth/Passkey/BiometricCredential` Keychain `biometryCurrentSet`, `Info.plist surafoster` + LiveActivity + `entitlements` prod APNs + `PrivacyInfo` 10 types, `project.yml 2.2.1(40)`, 15 test files (gates/auth/version/rules/payroll/clock/reminders/jobs/tasks/parsing/TFN).
