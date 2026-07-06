# Tasks feature — Manager & Staff

## Overview

Managers create one-off/daily/weekly tasks, optionally assigned to specific
staff, with priority, due time, an optional reference photo, and a per-task
choice of **photo proof** or **tick-to-complete**. Staff complete tasks from
their Tasks tab; managers review live, can request a redo, and manage the
photo lifecycle below.

## Data model (Firestore)

`tasks` (see `Models/RosterTask.swift`): legacy fields plus optional
`assignedTo` (nil/empty = all staff), `dueTime` ("HH:mm"), `priority`
(low/normal/high), `requiresPhoto` (nil = true), `endDate`.

`task_completions` (doc ID `{taskId}_{date}` — one completion per task per
day, shared across assignees): legacy fields plus optional `note`, `status`
("completed"/"redo"), `redoReason`, `reviewedBy/At`, `managerDownloadedAt`,
and `staffPhotoUrls` (up to 4 proof photos; the first is mirrored to the
legacy `staffPhotoUrl` field for PWA compatibility).

Rules:
- Firestore (`docs/reference/firestore.rules.deployed`): staff can only write
  completions as themselves and cannot overwrite another staff member's
  completion; tasks are manager-write-only.
- Storage (`docs/reference/storage.rules`): staff create proof photos only
  under `task_photos/{uid}/...`, managers read/delete proof photos, and
  authenticated users can read manager reference photos.

`staffPhotoUrl` is kept as the shared field name for PWA/iOS compatibility.
New iOS proof photos store a `gs://...` Firebase Storage reference; legacy
HTTPS download-token URLs are still supported when reviewing older completions.

## Workflow

1. Manager creates/edits tasks (Tasks tab **+**, or Dashboard → New Task).
2. Task appears for assigned staff on its active days; completed via photo
   (in-app camera only, never the gallery) or tick, with an optional note.
3. Manager reviews the completion report; can **Request redo** (reopens the
   day, deletes the cloud photo, shows the reason to staff) or approve
   implicitly by deleting the cloud photo after review.
4. Recurring tasks reset each day; pause/resume via `active`, stop via
   `endDate`; delete keeps completion history.

## Photo lifecycle (Firebase free tier)

- Staff may attach up to **4 photos per completion**
  (`RosterRepository.maxPhotosPerCompletion`), each compressed to
  **<= 2 MB** (`Services/ImageCompressor.swift`: downscale to 1600 px +
  stepped JPEG quality). Local cache files are `{taskId}_{date}.jpg` for the
  first photo and `{taskId}_{date}_pN.jpg` for extras.
- Photos live only in the app sandbox (`Services/TaskPhotoCache.swift`),
  never the phone photo library.
- New proof photo records store a `gs://` Storage reference so manager review
  uses Firebase Storage rules instead of a broadly reusable download-token URL.
- **Staff**: local copy is viewable until the end of the week it was taken;
  a launch-time sweep deletes older ones, after which staff see a
  "Photo submitted" placeholder (staff views never re-download from cloud).
- **Manager**: downloads each photo once (stamping `managerDownloadedAt`),
  then serves it from the sandbox; local review history kept 90 days.
- **Cloud cleanup**: manager's "Reviewed — delete photo from cloud" button
  removes the Storage object immediately; a launch-time backstop deletes any
  photo first downloaded more than 14 days ago.

## Key files

- Staff UI: `Features/Tasks/TasksView.swift`
- Manager UI: `Features/Manager/Tasks/ManagerTasksView.swift`,
  `ManagerTaskEditorSheet.swift`, `ManagerTaskDetailSheet.swift`
- Data layer: `Services/RosterRepository.swift` (saveTask, completeTask,
  requestTaskRedo, deleteTaskCloudPhoto, cleanupExpiredTaskCloudPhotos)
- Tests: `RosterStaffTests/RosterTaskTests.swift`
