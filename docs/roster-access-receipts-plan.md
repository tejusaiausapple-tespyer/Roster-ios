# Roster Access Receipts — Deferred Design Plan

> **Status:** Deferred. Planning note only; not approved for implementation.
>
> **Important:** Do not add roster-view tracking, background monitoring, receipt
> storage, manager controls, or related notifications until the owner explicitly
> approves the feature and the legal/privacy gates below have been completed.

## Purpose

The proposed feature would let a manager request a limited report showing when a
specific roster version was successfully displayed in a staff member's authenticated
app. The staff member would be notified of each request and would authorise access
using a short-lived one-time code shown inside the app.

This feature must be described as a **Roster Access Receipt**, not proof that the
staff member read, understood, or remembered the roster. A missing receipt must not
be treated as proof that the roster was not seen because the device may have been
offline, the app may have failed to load, or the staff member may have used another
channel.

## Product and Privacy Principles

1. No hidden or continuous employee monitoring.
2. Tell staff what is collected before collection starts.
3. Show the staff member the manager, reason, date range, and fields requested before
   disclosing a report.
4. Collect only roster-display events; never collect GPS, keystrokes, camera,
   microphone, unrelated app activity, or screen recordings for this feature.
5. Use server-confirmed time and an immutable roster revision identifier.
6. Restrict reports to the requested staff member and date range.
7. Log every request, approval, decline, expiry, failed code attempt, and report view.
8. Provide staff with a way to view and dispute their own receipt history.
9. Apply a documented retention and deletion schedule.
10. Do not claim that an access receipt proves comprehension.

## Proposed User Flow

### Manager

1. Open the future **Validating** area under Insights & Pay.
2. Select one staff member and a limited roster date range.
3. Enter a required business reason.
4. Select **Request access receipt**.
5. The request remains Pending until the staff member approves, declines, or it
   expires.
6. Enter the one-time code supplied by the staff member.
7. View a read-only report whose heading states:
   `Roster displayed on the authenticated staff account`.

### Staff

1. Receive a generic push notification that does not contain the code or sensitive
   report details.
2. Open the app. If push notifications are disabled or delivery fails, show the
   pending request in-app the next time the authenticated account opens.
3. See a modal containing the requesting manager, purpose, requested period, data
   fields, retention information, and **Approve** / **Decline** actions.
4. On approval, display a four-digit one-time code to give to the manager.
5. Allow the staff member to view the resulting access record and submit a dispute or
   correction request.

### One-Time Code Controls

A four-digit code is acceptable only with all of these protections:

- Single use and generated with a cryptographically secure random generator.
- Five-minute expiry.
- Maximum five attempts, followed by request invalidation.
- Bound to the staff ID, manager ID, organisation, request ID, and requested period.
- Store only a salted hash of the code.
- Never place the code in the push payload, logs, analytics, or crash reports.
- Consume and invalidate the challenge atomically when successfully verified.
- Rate-limit request creation per manager and staff member.

A six-digit code would provide better resistance to guessing and should be reconsidered
before implementation.

## What an Access Receipt May Contain

| Field | Purpose |
|---|---|
| `receiptId` | Immutable unique identifier |
| `organisationId` | Tenant isolation |
| `staffId` | Authenticated staff account |
| `rosterWeekKey` | Week that was displayed |
| `rosterRevisionId` or hash | Exact roster version displayed |
| `surface` | `rosterTab` or an explicitly supported Home roster card |
| `serverReceivedAt` | Authoritative timestamp |
| `clientOccurredAt` | Diagnostic only; never authoritative |
| `appVersion` and `platform` | Diagnose version-specific failures |
| `eventSignature` | Detect alteration of the stored receipt |

Do not store raw device identifiers. If a per-installation identifier is necessary for
integrity or duplicate suppression, use a rotating pseudonymous identifier and document
it in the privacy assessment.

For a Home roster card, only record a display after a defined visibility threshold,
such as at least 50% visible for two seconds. Merely receiving a notification or
loading Home in the background is not a roster display.

## Storage Decision

Device-only storage is not suitable as the sole evidence source. A device record can
be lost, deleted, clock-adjusted, restored from backup, or modified. The preferred
design is an append-only server receipt created after the relevant roster version has
successfully rendered.

The existing Firebase/Firestore backend could store the receipts, or a separately
approved Cloudflare Worker and D1 database could be used to avoid Firebase quota.
Using Cloudflare would make it a disclosed data processor and requires review of data
location, contractual protections, access controls, retention, deletion, incident
response, and cross-border disclosure wording.

The staff approval code controls **manager disclosure of the report**. It does not
retroactively make undisclosed collection lawful, so the collection notice must be
presented before any roster-display receipts are recorded.

## Proposed Backend Objects

Names are provisional and must be finalised with the selected backend.

### `rosterAccessReceipts`

Append-only receipt records. Staff can read their own records. Managers cannot query
them directly; report access must go through the authorised request endpoint.

### `rosterReceiptRequests`

Contains the manager, staff member, requested period, reason, lifecycle state,
expiry, code hash, attempt count, approval metadata, and audit timestamps.

Suggested lifecycle:

`pending -> approved -> consumed`

Alternative terminal states:

`declined`, `expired`, `locked`, `cancelled`

### `rosterReceiptAuditEvents`

Append-only events for request creation, staff decision, code attempts, report access,
export, dispute, and administrative correction. Corrections must be appended and must
not rewrite the original event.

## Proposed API Surface

- `POST /api/roster-access/receipts`
  - Called only after a roster revision is successfully displayed.
  - Idempotent by staff, roster revision, surface, and display session.
- `POST /api/roster-access/requests`
  - Manager-only; creates a scoped request and notification.
- `GET /api/roster-access/requests/pending`
  - Staff-only; provides reliable in-app fallback when APNs is unavailable.
- `POST /api/roster-access/requests/{id}/approve`
  - Staff-only; creates the expiring code challenge.
- `POST /api/roster-access/requests/{id}/decline`
  - Staff-only.
- `POST /api/roster-access/requests/{id}/verify`
  - Manager-only; verifies and consumes the code atomically.
- `GET /api/roster-access/requests/{id}/report`
  - Available only after successful verification and only to authorised roles.
- `POST /api/roster-access/receipts/{id}/disputes`
  - Staff-only correction/dispute channel.

Every endpoint must authenticate the current user on the server and derive their role,
organisation, and user ID from the verified token rather than trusting request-body
identifiers.

## Expected iOS and Mac Code Changes

No files listed here should be changed until implementation is approved.

### Shared models

- Add `RosterAccessReceipt`, `RosterReceiptRequest`, `RosterReceiptRequestStatus`,
  `RosterReceiptReport`, and dispute/audit models under `Rosterra/Models/`.
- Keep validation and display wording in shared business rules so iOS and Mac behave
  consistently.

### Networking and repository

- Add typed endpoints to `Rosterra/Services/WorkerAPIClient.swift` if the Cloudflare
  design is selected.
- Add role-scoped state and actions to `Rosterra/Services/RosterRepository.swift`.
- Do not add a broad listener containing every employee's receipts to the manager
  repository. Fetch only an authorised report for one request.
- Add retry-safe, idempotent receipt submission with an offline queue if required.

### Staff UI

- Add the pre-collection notice and staff history/access controls to
  `Rosterra/Features/Account/AccountView.swift` and the Mac equivalent.
- Add a shared request-detail modal containing Approve and Decline.
- Connect roster-render completion in `Rosterra/Features/Roster/RosterView.swift` and
  `Rosterra/Mac/Screens/Staff/MacStaffRosterView.swift` only after the disclosure gate
  has been satisfied.
- If Home receipts are later approved, use a deliberate visibility threshold rather
  than a scroll callback alone.

### Manager UI

- Add a future **Validating** destination to manager navigation, including Mac.
- Build staff/date selection, reason entry, pending status, code entry, read-only
  report, export controls, and request audit history.
- Never show a global employee activity feed.

### Notifications and routing

- Register a `roster-access-requested` event with the Worker notification registry.
- Extend `Rosterra/Services/NotificationService.swift` and
  `Rosterra/ViewModels/AppRouter.swift` so a notification opens the request detail.
- Use `Rosterra/Features/Home/NotificationsSheet.swift` as an additional authenticated
  entry point.
- Treat APNs as best-effort and always retain an in-app pending-request fallback.

### Privacy and release material

- Update `Rosterra/Features/Shared/PrivacyPolicyView.swift` only after the approved
  legal wording is supplied.
- Review `Rosterra/Resources/PrivacyInfo.xcprivacy`, App Store Connect privacy answers,
  the public website privacy policy, employee monitoring policy, and App Review notes.
- Usage events linked to a staff account will likely need to be declared as Product
  Interaction/Usage Data used for App Functionality.

## Security and Authorisation Requirements

- Tenant isolation on every query and mutation.
- Staff may read only their own receipt history and requests.
- A manager may request records only for staff in their organisation.
- No direct client writes to immutable audit records unless the server verifies and
  signs the event.
- Encryption in transit and at rest.
- Secrets and code hashes excluded from application logs and analytics.
- Server timestamps for all security decisions.
- Replay protection, idempotency keys, rate limits, and atomic verification.
- Least-privilege administrative access with access logging.
- Documented retention deletion job and legal-hold procedure.
- Exported reports must include their scope, generation time, limitations, and an
  integrity identifier.

## Legal and Release Gates

Implementation must remain blocked until all of these are complete:

- [ ] Australian employment/privacy lawyer reviews the exact collection, consent or
      acknowledgement model, employee policy, report wording, retention, and dispute
      process.
- [ ] Review covers South Australian surveillance law and every other jurisdiction in
      which the app will be used, especially employee-owned devices.
- [ ] Determine whether staff approval is optional consent or acknowledgement under a
      workplace policy. Do not mix the two concepts.
- [ ] Privacy impact assessment identifies the employer, Rosterra, and infrastructure
      providers' respective roles and responsibilities.
- [ ] Final staff collection notice is approved and shown before collection begins.
- [ ] Privacy policy, workplace monitoring policy, App Store privacy answers, and
      processor disclosures are updated consistently.
- [ ] Retention period and deletion/dispute process are formally approved.
- [ ] Firestore rules or Worker/D1 authorisation receive an independent security
      review.
- [ ] Apple App Review notes explain the employment purpose, transparent request flow,
      and data minimisation.
- [ ] Feature flag defaults to disabled and supports an immediate server-side kill
      switch.
- [ ] Pilot is completed with test accounts before any production organisation is
      enabled.

Official references to revisit during review:

- [OAIC — Workplace monitoring and surveillance](https://www.oaic.gov.au/privacy/your-privacy-rights/surveillance-and-monitoring/workplace-monitoring-and-surveillance)
- [OAIC — Employee records exemption](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/employee-records-exemption)
- [OAIC — APP 5 notification requirements](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-5-app-5-notification-of-the-collection-of-personal-information)
- [South Australia — Surveillance Devices Act 2016](https://www.legislation.sa.gov.au/_legislation-documents/lz/c/a/surveillance-devices-act-2016/current/2016.2.auth.pdf)
- [Apple — App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

## Test Plan for a Future Implementation

### Unit and integration

- Receipt is created only after successful display of a concrete roster revision.
- Background launch, push receipt, failed load, or partial render creates no receipt.
- Duplicate display callbacks do not create duplicate receipts.
- Manager cannot request another organisation's staff member.
- Staff cannot approve another staff member's request.
- Code expiry, attempt limit, replay protection, atomic consumption, and request rate
  limits work correctly.
- Date range and organisation cannot be changed after staff approval.
- Declined, expired, cancelled, and locked requests cannot produce reports.
- Report returns only the approved staff member, period, and fields.
- Original receipts cannot be edited or deleted through normal client APIs.
- Retention deletion and dispute/correction append flows are verified.

### UI and device

- Foreground and background notification flows on iPhone, iPad, and Mac.
- Pending request remains discoverable when notification permission is denied or APNs
  does not deliver.
- Staff disclosure is readable with Dynamic Type, VoiceOver, and reduced motion.
- Sensitive information and the code do not appear on the lock screen.
- Manager and staff sessions switching accounts cannot leak request data.
- Offline, expired-session, restored-device, and multiple-device behaviour is defined
  and tested.

### Privacy and abuse

- No event is recorded before the approved collection notice takes effect.
- No GPS, keystroke, background-use, or unrelated screen telemetry is transmitted.
- Repeated manager requests trigger rate limits and auditable alerts.
- Staff can see who requested and accessed their report.
- Report language consistently describes evidence and limitations without claiming
  proof of comprehension.

## Delivery Order After Future Approval

1. Complete legal review and privacy impact assessment.
2. Approve wording, retention, dispute policy, and backend choice.
3. Implement server schema, authentication, authorisation, audit log, and kill switch.
4. Add shared models and typed API client.
5. Add staff notice, request approval, code display, history, and dispute UI.
6. Add manager request, code verification, and read-only report UI.
7. Add narrowly scoped roster-display receipt generation.
8. Update privacy/release materials and App Store Connect disclosures.
9. Run security, accessibility, abuse, offline, and multi-device tests.
10. Release behind a disabled feature flag, pilot, review results, then explicitly
    approve any wider rollout.

