# Staff App Structure (Android parity)

Maps the **iOS Staff shell** to Android destinations. Extra tabs named in the brief (Shifts, Notifications, Profile, Settings as separate roots) are **nested destinations**, matching iOS — not separate bottom tabs — unless a later UX review changes this.

---

## Bottom navigation (required)

| Tab | Purpose | Root composable (planned) |
|-----|---------|---------------------------|
| **Home** | Dashboard, clock, hours, upcoming, notification entry | `HomeScreen` |
| **Roster** | Weekly published shifts + timesheet actions | `RosterScreen` |
| **Tasks** | Assigned tasks + photo completion | `TasksScreen` |
| **Availability** | Weekly availability editor | `AvailabilityScreen` |
| **Account** | Profile, payslips, settings, security, legal | `AccountScreen` |

---

## Per-destination specification

### Home

| | |
|--|--|
| **Purpose** | Orient staff for today: clock, actions, hours, upcoming |
| **Screens** | `HomeScreen`; sheet `NotificationsSheet`; dialogs from `ClockInCard` |
| **User actions** | Open notifications; start/break/end shift; submit hours (route); add to calendar; pull refresh; jump to roster |
| **Firestore reads** | Own shifts, timesheets, attendance, messages, daily jobs, settings/app+locations |
| **Firestore writes** | Attendance clock in/out; message read (from sheet); daily job toggle |
| **Cached data** | Listener snapshot + Room mirror of shifts/timesheets/messages/jobs; clock session DataStore |
| **Refresh** | Snapshot listeners continuous; pull → `refreshFromServer`; clock session local |
| **Offline** | Show cache; clock locally; attendance sync when online; calendar ICS fallback |

### Roster (“Shifts” content lives here)

| | |
|--|--|
| **Purpose** | Browse published shifts by week; submit/edit/resubmit hours; report/undo absence |
| **Screens** | `RosterScreen` → `HistoryScreen`; sheets `SubmitHoursSheet`, `ReportAbsenceSheet` |
| **User actions** | Week nav; swipe/menu actions; history; calendar; deep-link open submit/absent |
| **Firestore reads** | Own published shifts (date window); own timesheets; clock session for prefill |
| **Firestore writes** | Timesheet create/update/delete (absence undo); Worker notify |
| **Cached data** | Shifts + timesheets Room/Firestore cache |
| **Refresh** | Listeners; pull refresh; deep-link one-off `fetchShift` if outside window |
| **Offline** | View cache; writes require network (show error, keep sheet open) |

### History (nested under Roster)

| | |
|--|--|
| **Purpose** | Searchable timesheet history + hour summaries |
| **Screens** | `HistoryScreen` |
| **User actions** | Filter period/status; search; resubmit rejected |
| **Firestore reads** | Own timesheets (already listening) |
| **Writes** | None directly (resubmit opens Roster sheet) |
| **Cache / refresh / offline** | Same as Roster timesheet cache |

### Tasks / Jobs

| | |
|--|--|
| **Purpose** | Complete assigned roster tasks with photo proof; Daily Jobs live primarily in Notifications sheet (iOS parity) |
| **Screens** | `TasksScreen` + `TaskDetailSheet` + camera; Daily Jobs in `NotificationsSheet` |
| **User actions** | Select day; open task; capture ≤4 photos; note; complete; toggle daily jobs |
| **Firestore reads** | `tasks` (active), `task_completions` (window), `daily_job_assignments` (own) |
| **Writes** | Completions + Storage uploads; daily job completed fields; Worker `task-completed` / `jobs-all-completed` |
| **Cached data** | Task defs/completions; local proof files; Coil for ref photos |
| **Refresh** | Listeners; no silent gallery pick in production builds (camera primary) |
| **Offline** | List from cache; complete requires network |

### Availability

| | |
|--|--|
| **Purpose** | Declare weekly availability for roster planning |
| **Screens** | `AvailabilityScreen` + `DayEditSheet` |
| **User actions** | Week nav (−2…+12); edit day; recurring; reset; save |
| **Firestore reads** | Own `users/{uid}.weeklyAvailability`; `settings/availabilityLocks` |
| **Writes** | **Worker only** `POST /api/staff/availability` (not direct Firestore) |
| **Cached data** | User profile + locks |
| **Refresh** | User listener; after save optimistic merge |
| **Offline** | View only; save blocked with clear error |

### Notifications (not a tab)

| | |
|--|--|
| **Purpose** | Message inbox + Daily Jobs progress |
| **Screens** | `NotificationsSheet` / full-screen on compact if needed |
| **User actions** | Mark read (implicit/on open); complete/undo daily jobs |
| **Firestore reads** | Own messages (30d); own daily jobs |
| **Writes** | `read: true`; daily job completed fields |
| **Cached data** | Messages + jobs |
| **Refresh** | Listeners; badge on Home |
| **Offline** | Read cache; writes when online |

### Payslips (under Account)

| | |
|--|--|
| **Purpose** | View submitted/archived payslips; share PDF |
| **Screens** | `PayslipsScreen` + PDF viewer |
| **User actions** | Month pick; open PDF; share/print; pull refresh |
| **Firestore reads** | Own payslips month query |
| **Writes** | None |
| **Cached data** | Month results + downloaded-month markers |
| **Refresh** | Cache-first; force on pull / first view of current month |
| **Offline** | Previously fetched months only |

### Profile + Settings (Account tab)

| | |
|--|--|
| **Purpose** | Identity, security, appearance, legal, account lifecycle |
| **Screens** | `AccountScreen`; sheets change password/email; verify password; legal; deletion confirm |
| **User actions** | Photo local pick/remove; email/password; biometric toggle; notification preference; dark mode; deletion request; sign out |
| **Firestore / Auth / Worker** | Profile allow-list update; Auth email/password; Worker deletion request; FCM token docs |
| **Cached data** | Profile listener; local photo; DataStore prefs |
| **Offline** | View local settings; network for auth/deletion |

---

## Cross-cutting navigation graph (planned)

```
AuthGraph: Login → ForcedPassword → ProfileCompletion → DeviceUnlock
StaffGraph:
  Home
    └─ NotificationsSheet
  Roster
    ├─ History
    ├─ SubmitHoursSheet
    └─ ReportAbsenceSheet
  Tasks
    └─ TaskDetail / Camera
  Availability
    └─ DayEditSheet
  Account
    ├─ Payslips → Pdf
    ├─ ChangePassword / ChangeEmail
    ├─ Privacy / Terms
    └─ DeleteAccount
```

Deep links must resolve into this graph with the same event→tab mapping as iOS (`04-notifications.md`).

---

## Brief vs iOS naming

| Brief name | Android / iOS reality |
|------------|------------------------|
| Shifts | Content on **Home** (today/upcoming) + **Roster** (week) |
| Jobs / Tasks | **Tasks** tab + Daily Jobs in **Notifications** |
| Notifications | Sheet / destination from Home badge — not bottom tab |
| Profile / Settings | Combined **Account** tab |
| Payslips | Nested under Account |
