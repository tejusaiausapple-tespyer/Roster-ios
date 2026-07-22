# Local Cache, Performance & Security

---

## 1. Principles

1. **Minimise Firestore reads** — staff-scoped queries only; date windows; no all-staff listeners.  
2. **Offline-first UI** — render Room/Firestore cache immediately; sync in background.  
3. **Server rules are law** — client checks are UX, not security.  
4. **Optimistic UI sparingly** — mirror iOS: availability after Worker success; cancel reminders after confirmed writes.  
5. **Idempotent writes** — timesheet doc IDs = shift IDs where iOS does; attendance doc ID = shift ID.

---

## 2. Recommended local architecture

```
UI (Compose)
  ↓ StateFlow
ViewModel
  ↓
StaffRepository
  ├── FirestoreDataSource (listeners + get)
  ├── WorkerDataSource (Retrofit/Ktor)
  ├── StorageDataSource (task photos)
  ├── Room (StaffDatabase)
  └── DataStore / EncryptedSharedPreferences / Keystore
```

### Room entities (initial)

| Entity | Source | Invalidate when |
|--------|--------|-----------------|
| `UserProfile` | `users/{uid}` | Profile snapshot |
| `ShiftEntity` | shifts listener | Snapshot / force refresh |
| `TimesheetEntity` | timesheets listener | Snapshot |
| `MessageEntity` | messages listener | Snapshot / mark read |
| `TaskEntity` | tasks listener | Snapshot |
| `TaskCompletionEntity` | completions | Snapshot / complete |
| `DailyJobEntity` | assignments | Snapshot / toggle |
| `AttendanceEntity` | attendance | Snapshot / clock |
| `AppSettingsEntity` | settings/app | Snapshot |
| `LocationEntity` | settings/locations | Snapshot |
| `AvailabilityLockEntity` | availabilityLocks | Snapshot |
| `PayslipEntity` | month fetch | Month refresh |

### DataStore / secure prefs

| Key | Purpose |
|-----|---------|
| Clock session JSON | Offline clock |
| Theme | Appearance |
| Last manual login | Biometric freshness |
| Last FCM token | Logout cleanup |
| Payslip months downloaded | Offline months |
| Device auth enabled | Per uid |

### Image cache

- Coil disk/memory for reference photos  
- App-specific dir for task proof JPEGs; sweep older than current week on session start (iOS parity)

---

## 3. Listener & refresh strategy

| Data | Strategy |
|------|----------|
| Core staff collections | Continuous snapshot listeners while Staff session active |
| Payslips | Cold cache-first per month; network if missing/forced |
| Deep-link shift outside window | One-shot get + verify `staffId` + published |
| Pull-to-refresh | `get` with server source / wait for pending writes; **non-fatal** errors |
| App foreground | Rely on listeners; optional light refresh debounce |

**Intelligent intervals:** prefer push-driven listeners over polling. Use WorkManager only for reminder reschedule / token refresh / failed write retry — not for primary roster sync.

---

## 4. Offline write policy

| Write | Offline policy |
|-------|----------------|
| Clock session mutations | **Allowed locally**; queue attendance sync |
| Timesheet / absence | Block with error (or explicit outbox in later phase) |
| Availability | Block (Worker) |
| Task complete + photos | Block until upload possible; keep captured images local |
| Message read | Best-effort queue OK |
| Daily job toggle | Best-effort queue OK |
| Auth / deletion | Block |

**Retry:** exponential backoff for attendance sync & token sync; surface persistent failures in Clock UI (iOS alert parity).

---

## 5. Performance tactics

- Lazy lists (`LazyColumn`) for roster days, history, tasks, payslips  
- Pagination not required initially (windows already bounded); history filters client-side like iOS  
- Compress task photos before upload (max dimension 1600, ≤2MB JPEG)  
- Avoid re-downloading staff proof photos (local-only display)  
- Network monitor (`ConnectivityManager`) → banner “Offline — showing saved data”  
- Debounce week switching loads (data already in memory/Room)  
- Crashlytics on; no PII in custom keys beyond uid if required for support  

---

## 6. Security review (every Staff interaction)

| Interaction | Staff OK? | Guard |
|-------------|-----------|-------|
| Listen own shifts | Yes | Query `staffId` + published |
| Listen all shifts | **No** | Do not implement |
| Submit timesheet | Yes | Field allow-list; no approval fields |
| Approve timesheet | **No** | No API |
| Save availability via Worker | Yes | Auth bearer; self `userId` only |
| Save availability direct Firestore | **No** | Rules deny; don’t call |
| Upload task photo under other uid path | **No** | Path must equal auth uid |
| Read wages | **No** | No repository method |
| Read other payslips | **No** | Query always `staffId==uid` + status filter |
| Create staff via Worker | **No** | Omit client endpoints |
| Open manager deep link | **No** | Mapper no-op |
| Bypass device unlock | **No** | Gate before Staff graph |

### Privilege escalation tests

Add androidTest cases that:

1. Sign in as staff test user  
2. Attempt forbidden Firestore writes (expect permission-denied)  
3. Assert navigation to manager routes impossible  

---

## 7. Secrets & config

- `google-services.json` in app module (not committed if policy requires CI inject)  
- API base `https://sura-roster.com`  
- No Worker admin keys in app  
- Certificate pinning optional later; HTTPS required  

---

## 8. Privacy / Play Data safety (later milestone)

Align declarations with iOS App Privacy: contact info, location (clock), photos (tasks), user content, financial (payslips/TFN retained server-side), user ID, crash diagnostics — **no ads / no tracking SDK**. Document in Play Console when shipping.
