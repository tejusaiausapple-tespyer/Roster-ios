# Backend reference snapshots

Copies of the backend definition files from the PWA repo
(`~/Desktop/Projects/Roster - 5 july /Roster`), which is the source of truth
and where deploys happen (`firebase deploy --only firestore,storage`, `wrangler deploy`).
Re-copy after backend changes so this native repo documents what it runs against.

## How Firebase rules are actually deployed (learned the hard way, 2026-07-06)

`firebase deploy` only deploys the targets listed in the `firebase.json` of the
**directory you run it from** — "No targets in firebase.json match '--only
storage'" means that directory's firebase.json has no `storage` section, not
that the command is wrong.

- **Preferred:** deploy from the PWA repo root (`~/Desktop/Projects/Roster - 5
  july /Roster`) — but its `firebase.json` and rules files must be current.
  The Storage rules work landed in THIS repo first, so the PWA repo's
  firebase.json was missing the `storage` target and the deploy failed there.
  Keep the PWA repo's `firebase.json` + `storage.rules` + `firestore.rules` in
  sync with the copies here before deploying from it.
- **Working fallback:** this directory (`docs/reference/`) is itself a valid
  deploy root — its `firebase.json` declares both `firestore` and `storage`
  targets against the files in this folder:
  `cd ~/Desktop/RosterStaff/docs/reference && firebase deploy --only storage --project roster-8a270`

**Cross-service gotcha:** `storage.rules` calls `firestore.get()/exists()`.
That requires a one-time IAM grant — the Storage service agent
(`service-641001375488@gcp-sa-firebasestorage.iam.gserviceaccount.com`) needs
the *Firebase Rules Firestore Service Agent* role. The CLI prompts for this on
an interactive deploy (answer Yes). Without it, every rule that touches
Firestore evaluates to **deny** and the app gets "User does not have
permission to access gs://…" on both uploads and reads, even with correct
rules deployed. Granted for roster-8a270 on 2026-07-06.

| File | Source | Purpose |
|------|--------|---------|
| `firestore.rules.deployed` | `firestore.rules` | Security rules the app's reads/writes must satisfy (includes `shift_attendance`) |
| `storage.rules` | `storage.rules` | Security rules for task proof/reference photos in Firebase Storage |
| `firestore.indexes.json` | same name | Composite indexes the app's queries rely on |
| `firebase.json` | same name | Firebase deploy targets, including Firestore + Storage rules |
| `worker-notifications.ts` | `worker/handlers/notifications.ts` | Notification event names/payloads the app sends to `/api/send-notification` (`shift-started` / `shift-ended` pending Worker support) |
