# Staff Permissions Matrix

Android must enforce these restrictions in **navigation**, **repository queries**, and **API clients**. Server rules remain authoritative; the client must never “try” manager operations.

---

## A. What Staff MAY do

### View

| Resource | Scope |
|----------|-------|
| Own profile (`users/{uid}`) | Full own document (UI must not surface TFN even if present) |
| Own published shifts | `staffId == uid`, status published, staff date window |
| Own timesheets | `staffId == uid` |
| Own shift attendance | `staffId == uid` |
| Own messages | `recipientId == uid` |
| Own daily job assignments | `staffId == uid` |
| Active tasks | Rules allow all active; **UI shows only assigned to self** |
| Task completions in window | Prefer own/`completedBy` in UI |
| Settings docs | `settings/app`, `locations`, `availabilityLocks` (read-only) |
| Own payslips | `staffId == uid` AND status `submitted` \| `archived` |
| Manager task reference photos | Via Storage download URL |
| Own push token docs | Subcollection under own user |

### Create / Submit

| Action | Notes |
|--------|-------|
| Timesheet submit | After submittable (or verified clock-out rules); status `pending` |
| Absence report | `absent_reported`; gated by `BusinessRules` + rules |
| Clock-in attendance | Own assigned published shift |
| Task completion | `completedBy == uid`; optional photos |
| Push token doc | Own token only |
| Account deletion **request** | Via Worker only |

### Edit / Update

| Action | Notes |
|--------|-------|
| Profile allow-list | `fullName`, `phone`, `dob`, `address`, `emergencyContact`, `theme`, `profileUpdateRequired`, `updatedAt`, `lastLoginAt` (match live rules) |
| Pending/rejected/draft timesheet | No approval fields; cannot set `approved`/`absent` manager statuses |
| Clock-out attendance | Merge own attendance fields |
| Message `read: true` | Only |
| Daily job completed trio | `completed`, `completedAt`, `completedBy` only |
| Availability | **Worker** `/api/staff/availability` only |
| Password / email | Firebase Auth (+ Worker password-complete) |

### Upload

| Action | Path |
|--------|------|
| Task proof photos | `task_photos/{uid}/…jpg` (JPEG, size limits) |

### Download / export

| Action | Notes |
|--------|-------|
| Payslip PDF | Generated locally from Firestore fields; share sheet |
| Calendar | Device calendar insert or `.ics` share |
| Task reference images | HTTPS / Coil cache |
| Own proof images | Local cache preferred; Storage rules allow own read |

### Sync

| Action | Notes |
|--------|-------|
| Snapshot listeners | Staff-scoped queries only |
| Pull-to-refresh | Force fetch own data |
| FCM token sync | On login / token refresh |
| Reminder reschedule | When shifts/timesheets/clock change |

---

## B. What Staff must NOT do

### Product surfaces (no routes, no UI)

- Manager dashboard / metrics for all staff  
- Manager roster editor (create/edit/move/copy/publish/bulk delete)  
- Manager timesheet approval / rejection / adjust  
- Staff management (create users, role changes, rates, TFN entry, status)  
- Availability week lock/unlock controls  
- Wage awards / earnings lines / staff wage profiles  
- Payroll generate / edit / submit / archive / correct  
- Manager reports / tenure admin / analytics dashboards  
- Business settings edit (company, ABN, locations, geofence config)  
- Task admin (create/edit/pause, reference photo upload, redo request)  
- Daily job **template** library & assignment management  
- Manager notification console  

### Data / API denies

| Denied | Why |
|--------|-----|
| Read/write other users’ `users/{id}` | Privacy |
| Read other staff shifts/timesheets/attendance/messages/payslips | Privacy |
| Write `shifts` | Manager-only |
| Write `tasks` / `daily_job_templates` | Manager-only |
| Write `settings/*` | Manager-only |
| Read/write `wages/**` | Financial admin |
| Write `payslips` | Payroll admin |
| Read/write `auditLogs`, `importBatches`, `masterSheets` | System |
| Set timesheet `approvedBy` / `approvedAt` / `managerNotes` / terminal manager statuses | Privilege escalation |
| Delete attendance | Rules forbid |
| Storage delete / manager `task_ref_photos` upload | Manager-only |
| Worker: `/api/create-auth-user`, `/api/delete-staff-users`, account-deletion approve/decline/cancel | Manager/admin |
| Hidden deep links into manager tabs | Ignore / no-op |

---

## C. Enforcement checklist (Android)

1. **Single role gate** after profile load: if `role == manager`, show “Use manager app / web” or block — **do not** load Manager UI in Staff app milestone.  
2. **Repository API** only exposes staff-scoped methods; no `listenAllShifts()` in Staff binary if avoidable.  
3. **ProGuard/R8** not a security boundary — assume rooted device; rely on rules.  
4. **Navigation** deep links whitelist staff destinations only.  
5. **Instrumented tests** attempt forbidden writes and assert failure.  
6. **Never** embed service-account or Worker admin secrets in the app.

---

## D. Known rules/UI mismatches (do not widen on Android)

- Tasks/completions globally readable by auth users under current rules; UI must still filter to assigned/own.  
- Email-change Firestore fields may be denied by rules snapshot — verify live before shipping.  
- Absence timing: implement `BusinessRules` + rules, not older guide text.
