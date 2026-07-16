# Rosterra — App Store Submission Notes

Reference for the App Store Connect (ASC) listing, App Review notes, and the
App Privacy questionnaire. Keep in sync with the app when data use changes.

App: Rosterra · Bundle ID: `com.surainvestments.roster` · Team: `GS2KGPX9P8`

---

## App Review notes (paste into ASC → App Review Information → Notes)

Rosterra is invite-only workforce software (staff scheduling, timesheets, and
payslips) used by a business and its employees. There is no public sign-up:
a manager creates staff accounts, and each staff member signs in with the
email/password their employer provides.

Demo account for review (staff and manager):

- Manager — email: <FILL IN>  password: <FILL IN>
- Staff — email: <FILL IN>  password: <FILL IN>

Account deletion (Guideline 5.1.1(v)):
Employee accounts are created by the business and deleted in-app.

Staff (employer-managed) — fully in-app:
1. Staff: Account → Delete account → request.
2. Manager: Staff → (select staff) → Account deletion → Approve.
3. Staff account locked immediately.
4. For 30 days the manager may Cancel & reinstate.
5. After 30 days a server job permanently deletes Firebase Auth login and push
   tokens.

Manager / business owner:
The signed-in manager is the business owner for this single-tenant deployment.
Owner accounts cannot self-delete (safety — deleting the owner would strand the
organisation). Staff deletion covers the accounts the app creates for employees.
When Rosterra moves to multi-tenant SaaS, owner/tenant closure will be wired to
a Super Admin console.

Retained for Australian tax / payroll (ATO) record-keeping — not deleted:
name, date of birth, address, Tax File Number (TFN, manager-only), employee ID,
timesheets, shifts, attendance, payslips, wage assignment history.

Privacy Policy: in-app (Account → About → Privacy Policy) and
https://sura-roster.com/privacy (last updated 16 July 2026).
Terms of Service: in-app (Account → About → Terms of Service) and
https://sura-roster.com/terms.

Permissions:
- Location (When In Use): captured only at shift clock-in/clock-out to verify
  attendance; not tracked in the background.
- Notifications: local shift/hours reminders scheduled from the last roster sync
  (still delivered after the app is closed) plus optional remote push. The app
  does not keep a process running after the user quits.
- Camera / Photo Library: optional profile photo and task/reference photos.
- Face ID: optional local app-unlock.
- Calendars (write-only): optionally add rostered shifts to the user's calendar.

No third-party advertising, no tracking (ATT not used).

---

## App Privacy questionnaire (ASC → App Privacy)

Tracking: No. (No cross-app/website tracking; ATT not requested.)

Data collected and linked to the user (not used for tracking):

- Contact Info: Name, Email address, Phone Number — App Functionality.
- Other Contact / Sensitive: Tax File Number (manager-entered for payroll/ATO)
  — App Functionality. (Declare as Other User Content or Financial Info as ASC allows.)
- Location: Coarse/Precise Location — App Functionality (attendance verification
  at clock-in/out only).
- User Content: Photos (profile photo, task/reference photos) — App Functionality.
- User Content / Other: Roster, timesheet, availability, payslip, DOB, address —
  App Functionality.
- Diagnostics: Crash Data (Firebase Crashlytics) — App Functionality.
- Identifiers: User ID (Firebase Auth uid) — App Functionality.

Note: The iOS app uses Firebase Auth, Firestore, Storage, Messaging, and
Crashlytics. It does NOT use Firebase Analytics (that is only on the web app).

---

## Encryption

`ITSAppUsesNonExemptEncryption = false` (standard HTTPS only; declared in
`Rosterra/Resources/Info.plist`).

---

## Listing

- Name: Rosterra
- Subtitle: Staff Scheduling & Shift Rosters
- Support URL: https://sura-roster.com/contact
- Marketing/Privacy Policy URL: https://sura-roster.com/privacy
- Description should make clear this is an invite-only employee/workforce app.

---

## Device verification — account deletion / ATO retention

1. Manager: set a test staff TFN in Staff → Tax; confirm masked when not editing.
2. Staff: Account → Request account deletion → status shows waiting.
3. Manager: Approve → staff cannot sign in; status locked; cancel deadline shown.
4. Manager: Cancel deletion & reinstate → staff can sign in again.
5. Re-approve; after test, set `deletion.cancelDeadlineAt` in the past (or wait)
   and confirm cron purges Auth but timesheets/payslips/name/TFN remain.
6. Confirm Settings “clear staff” schedules ATO-safe lock (does not wipe timesheets).
7. Deploy PWA so live `/privacy` and `/terms` match this lifecycle.

---

## Preflight checklist (before first upload)

- [ ] Branding pre-launch checks in `docs/BRANDING.md` (trademark, name/domain).
- [ ] A monitored `support@sura-roster.com` mailbox exists (or forwards to a real inbox).
- [ ] Deploy Worker + PWA with account-deletion APIs and updated privacy/terms.
- [ ] Device verification (above).
- [ ] Archive with production `GoogleService-Info.plist` and production push entitlement.
- [ ] ASC: screenshots, description, Support URL, Privacy URL, Age Rating,
      App Privacy answers (include TFN), and App Review notes (above).
- [ ] Submit to TestFlight (internal/external) before production.
