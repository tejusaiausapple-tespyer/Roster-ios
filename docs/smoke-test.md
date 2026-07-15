# Smoke Test — Regression Gate

Run this checklist before merging any milestone. Every step must pass on an iOS
Simulator (iPhone) at minimum; run on iPad and Mac Catalyst for milestones that
touch layout, signing, or the keychain.

## Prerequisites
- `GoogleService-Info.plist` present in `Rosterra/Resources/`
- One staff test account and one manager test account

## Staff flow
1. Launch app → login screen appears (no crash, orbs animate).
2. Sign in with the staff account → lands on Home with greeting + 5 tabs
   (Home, Roster, Tasks, Availability, Account).
3. Roster tab → week selector navigates back/forward; shifts render for the
   correct days; "View Shift History" opens History.
4. On a submittable shift (past end time), swipe → Submit Hours → adjust
   times/break → submit → status pill becomes "Pending review".
5. On a future shift, swipe → Report Absence → submit → "Absence reported";
   then Undo absence → report removed.
6. Tasks tab → today's tasks listed; open one → camera/photo → Complete Task
   → shows completed with timestamp.
7. Availability tab → next week → edit a day → Save → success toast.
8. Account tab → toggle Face ID unlock on (verify prompt) and off.
9. Sign out → returns to login.

## Manager flow
10. Sign in with the manager account → lands on Manager UI (Dashboard).
11. Roster tab → create a draft shift → it appears in the grid/agenda →
    publish it → verify (on a staff device/simulator) the shift appears for
    that staff member.
12. Timesheets tab → open the pending timesheet from step 4 → Approve →
    staff's History shows "Approved".
13. Staff tab (iPad sidebar, or Account → Management on iPhone) → open a
    staff member → edit phone (pencil → checkmark) → saves.
14. Reports and Availability tabs render without errors.
15. Sign out.

## Cross-cutting
16. Kill and relaunch the app → session restores without re-login (and the
    biometric gate appears if it was enabled).
17. Airplane mode → previously loaded data still renders from cache; writes
    fail with a visible error (post Milestone 5) rather than crashing.
