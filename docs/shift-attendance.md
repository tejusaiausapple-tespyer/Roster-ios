# Shift Attendance — Verified Clock-In/Out

Implemented in the iOS app (branch `wages-and-shift-flow`). This doc covers how it works and the **backend changes required** to activate it fully.

## How it works

- **End-shift confirmation**: ending a shift always shows a confirmation dialog ("Are you sure you want to end your shift?"), with an extra note when the rostered end time hasn't been reached. Accidental taps can't close a shift.
- **Server timestamps**: Start/End Shift writes `shift_attendance/{shiftId}` with `FieldValue.serverTimestamp()` for `clockInAt` / `clockOutAt`. Firestore stamps these on the server, so changing the phone clock cannot forge them. The device's own clock is stored alongside (`clockInDeviceAt` / `clockOutDeviceAt`); the manager portal flags any gap over 2 minutes as possible clock tampering.
- **GPS capture**: a when-in-use location fix is captured at both taps (`clockInLocation` / `clockOutLocation` GeoPoints, plus accuracy). If the shift's location matches a saved workplace with geofence coordinates, the fix is checked against the allowed radius (+GPS accuracy margin). Outside the fence (or with location denied), staff see a warning and must explicitly confirm; the verdict (`inside` / `outside` / `unknown`) and distance are recorded either way.
- **Geofence setup**: Manager Portal → Account → Locations → edit a location → "Attendance geofence": type the workplace address, tap *Find coordinates* (MKLocalSearch), choose a radius (100 m – 1 km).
- **Manager visibility**: the Timesheet Review sheet shows a **Verified Attendance** card — server clock-in/out times, geofence verdict, distance from workplace, map links, and the clock-skew warning. Records stream live via a `shift_attendance` listener.
- **Offline / failure behaviour**: the local timer session always works; if the attendance write fails, staff see a "recorded on device, couldn't sync" alert. Managers simply see no verified record — the absence of one is itself the signal.

## Backend changes required

### 1. Firestore rules — new `shift_attendance` collection

```
match /shift_attendance/{shiftId} {
  allow read: if isManager() || resource.data.staffId == request.auth.uid;
  // Staff may create/update only their own record, only for a shift
  // assigned to them, and may never write the server-time fields with
  // client-supplied values (serverTimestamp() satisfies this check).
  allow create, update: if request.auth != null
    && request.resource.data.staffId == request.auth.uid
    && get(/databases/$(database)/documents/shifts/$(shiftId)).data.staffId == request.auth.uid
    && (!('clockInAt' in request.resource.data.diff(resource == null ? {} : resource.data).affectedKeys())
        || request.resource.data.clockInAt == request.time)
    && (!('clockOutAt' in request.resource.data.diff(resource == null ? {} : resource.data).affectedKeys())
        || request.resource.data.clockOutAt == request.time);
  allow delete: if false;
}
```

Until these rules are deployed, staff writes to `shift_attendance` are denied — the app degrades gracefully (local session still works, sync alert shown).

### 2. Cloudflare Worker — manager notification events

The app fires best-effort `POST /api/send-notification` with new events after each successful attendance write:

- `{"event": "shift-started", "shiftIds": ["<shiftId>"]}` → notify managers "**[Staff Name] has started their shift.**"
- `{"event": "shift-ended", "shiftIds": ["<shiftId>"]}` → "**[Staff Name] has ended their shift.**"

Event names follow the Worker's existing hyphenated convention (see
`docs/reference/worker-notifications.ts`, which handles `roster-published`,
`timesheet-submitted`, etc.). The two shift events above are **not yet
implemented** in `worker/handlers/notifications.ts` — add branches there
mirroring the `timesheet-submitted` manager-notification path.

The Worker should resolve the staff name from the shift, then deliver via the `messages` collection (visible now) and push (once the Apple Developer account is approved — haptics for delivery/tap are already wired, see `NotificationService`).

### 3. Geofence trust model (advisory by design) + optional hardening

**By design, the geofence verdict is advisory, not an access control.** What is
tamper-*evident* and trusted are the pieces the server owns: `clockInAt`/`clockOutAt`
are `FieldValue.serverTimestamp()` (a manipulated device clock can't forge them), the
raw GPS `GeoPoint`s + accuracy are recorded verbatim, and the device clock is stored
alongside so the manager portal flags >2 min skew. The manager reviews all of this on
the Verified Attendance card and can sanity-check the recorded coordinates directly, so
a spoofed `inside`/`outside` verdict does not, on its own, buy a staff member anything —
this is a deliberate trust choice for a single-business deployment, not a gap.

**Optional hardening (only if you later want a hard block):** move the verdict
server-side — replace the direct Firestore write with a Worker endpoint
(`/api/attendance/clock-in|clock-out`) that receives the raw coordinates, computes
distance against the stored workplace, writes the record with its own clock, and can
*reject* out-of-fence actions. The iOS call sites (`RosterRepository.startShift/endShift`)
are the single place to swap.
