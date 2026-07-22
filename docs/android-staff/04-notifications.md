# Staff Notifications Plan

Parity target: iOS `NotificationService` + `ShiftReminderScheduler` + `AppRouter` routing.

---

## Goals

- Push (FCM) for server/Worker events  
- Local scheduled reminders for shift lifecycle  
- Deep link into correct Staff destination  
- Badge = unread messages + pending daily jobs (Home)  
- Notification history = in-app messages list (not a separate OS inbox UI)  
- Cancel/resync reminders on data change and logout  

---

## Channels (Android)

| Channel ID | Name | Importance | Use |
|------------|------|------------|-----|
| `roster_shifts` | Shift alerts | High | Shift reminders, start/end nudges |
| `roster_timesheets` | Timesheets | Default | Submit reminders, approved/rejected |
| `roster_roster` | Roster updates | Default | Published / changed / cancelled |
| `roster_tasks` | Tasks & jobs | Default | Assignments (if pushed), completions ack local optional |
| `roster_pay` | Payslips | Default | Payslip generated |
| `roster_general` | General | Default | Announcements / fallback |

Respect user disabling channels; Account screen deep-links to app notification settings.

---

## Push (FCM)

### Registration

1. Request notification permission (Android 13+)  
2. Obtain FCM token  
3. Write `users/{uid}/notificationTokens/{encodedToken}` with `token`, `platform: "android-native"`, `userAgent`, `enabled`, timestamps  
4. Delete token doc on logout; keep last token in DataStore for cleanup  

### Payload events Staff handle

| Event / kind | In-app route | Notes |
|--------------|--------------|-------|
| `roster-published` | Roster | |
| `shift-changed` | Roster | |
| `shift-cancelled` | Roster | |
| `timesheet-approved` | Roster | |
| `timesheet-rejected` | Roster + SubmitHours if shift id | |
| `timesheet-reminder` | Roster | Often Worker cron |
| `payslip-generated` | Account (Payslips) | |
| `shift-reminder` | Home or Submit per slot | Usually local, may also arrive remote |
| URL / path fields | Path mapper | Same as iOS |

### Payload events Staff ignore (manager-oriented)

`timesheet-submitted`, `timesheet-absent`, `shift-started`, `shift-ended`, `shift-running-late`, `shift-overtime-started`, `task-completed`, `jobs-all-completed`, `availability-updated` — Staff may **send** some of these via Worker after actions, but receiving them should not open manager UI.

### Foreground behaviour

- Show system notification or in-app banner (match UX decision); always update badge data from Firestore listeners  
- Optional haptic if payload `urgent`  

---

## Local scheduled reminders

Port `ShiftReminderScheduler` slots:

| Slot ID | When | Title intent | Deep link |
|---------|------|--------------|-----------|
| `24h` | 24h before start | Shift tomorrow | Home |
| `1h` | 1h before start | Shift soon | Home |
| `5m` | 5m before start | Ready to start? | Home |
| `forgot-start` | 10m after start if not clocked in | Forgot to start? | Home |
| `forgot-end` | 10m after end if still clocked in | Forgot to end? | Submit / Home |
| `submit-hours` | 15m after end if no timesheet/absence; also ended within 48h lookback | Submit hours | Roster submit |

**Limits:** max 8 upcoming shifts + 8 submit candidates (match iOS).  
**IDs:** `shift-reminder.{shiftId}.{slot}`  
**Resync:** on shifts/timesheets/attendance/clock changes; clear all on logout.  
**Not local (Worker):** 6h / 30m reminders per iOS comments.

Use `AlarmManager` + exact alarms only if justified; prefer `WorkManager` + notification scheduling APIs that survive reboot (`RECEIVE_BOOT_COMPLETED` reschedule). Document exact API choice in Phase N implementation notes.

---

## Deep linking

Support:

- Custom / App Links paths containing `home|roster|history|tasks|job|availability|account`  
- Query `submit=<shiftId>`, `absent=<shiftId>`  
- FCM data payload → same mapper  

Host submit/absence UI so it works if History is back-stacked (iOS NavigationStack gotcha).

---

## Badge counts

| Source | Counts toward |
|--------|---------------|
| Unread messages (`read == false`) | Home badge |
| Incomplete daily jobs for relevant dates | Home badge |
| OS launcher badge | Optional; sync with same formula if supported |

---

## Notification history

- **Source of truth:** Firestore `messages` for staff recipient  
- UI: Notifications sheet list + empty state  
- Mark read on view / tap (batch where possible)  
- Daily Jobs panel alongside messages (iOS parity)

---

## Account controls

- Explainer before first permission request  
- Toggle / open system settings if denied  
- Show pending local reminder summary (next reminder) when permitted — parity with iOS Account notifications section  

---

## Testing checklist

- [ ] Cold start from each push event lands correct tab/sheet  
- [ ] Rejected timesheet opens submit with correct shift  
- [ ] Clock-in cancels `forgot-start`; clock-out cancels `forgot-end`  
- [ ] Submit cancels `submit-hours`  
- [ ] Logout removes scheduled locals + token doc  
- [ ] Airplane mode: locals still fire if already scheduled  
- [ ] Android 13 permission denied path is graceful  
