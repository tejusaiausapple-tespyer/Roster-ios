# Payroll — Firestore rules addition (deployed 2026-07-10)

**Status: ✅ deployed** to `roster-8a270` via `firebase deploy --only firestore:rules`
from `docs/reference`. The block lives in `firestore.rules.deployed` alongside `wages`.

## Rules block

Add inside `match /databases/{database}/documents { ... }`, alongside the
existing `wages` block:

```
    // Payslips: manager-controlled payroll. Staff may ONLY read their own
    // SUBMITTED (or archived, i.e. superseded-but-published) payslips —
    // drafts, reviews and approvals are invisible to them. Staff can never
    // write. This is the security boundary for the whole payroll feature;
    // the client-side filtering is UX only.
    match /payslips/{payslipId} {
      allow read: if isManager() || (
        isAuthenticated() &&
        resource.data.staffId == request.auth.uid &&
        resource.data.status in ['submitted', 'archived']
      );
      allow write: if isManager();
    }
```

## Query compatibility

- Staff listener: `payslips where staffId == uid and status in ['submitted',
  'archived']` — both filters are equalities, so it satisfies the read rule
  for list queries and needs **no composite index** (zig-zag merge).
- Manager listener: `payslips where periodStart >= <26-weeks-ago>` — single
  field range, no composite index.

## Immutability note

The client never edits a payslip after `submitted` (corrections archive the
original and create a new draft doc). If server-side immutability is wanted
later, tighten the manager `update` to reject changes when
`resource.data.status == 'submitted'` except transitions to `'archived'`.

After deploying: update `docs/reference/firestore.rules.deployed` to match,
and tick this off in the workspace MEMORY "Pending Owner Actions".

**Done 2026-07-10** — also added `emailChangeRequired` to `isValidSelfUserUpdate`.
