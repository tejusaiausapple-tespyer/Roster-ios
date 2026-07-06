# Backend reference snapshots

Copies of the backend definition files from the PWA repo
(`~/Desktop/Projects/Roster - 5 july /Roster`), which is the source of truth
and where deploys happen (`firebase deploy --only firestore`, `wrangler deploy`).
Re-copy after backend changes so this native repo documents what it runs against.

| File | Source | Purpose |
|------|--------|---------|
| `firestore.rules.deployed` | `firestore.rules` | Security rules the app's reads/writes must satisfy (includes `shift_attendance`) |
| `firestore.indexes.json` | same name | Composite indexes the app's queries rely on |
| `firebase.json` | same name | Firebase deploy targets |
| `worker-notifications.ts` | `worker/handlers/notifications.ts` | Notification event names/payloads the app sends to `/api/send-notification` (`shift-started` / `shift-ended` pending Worker support) |
