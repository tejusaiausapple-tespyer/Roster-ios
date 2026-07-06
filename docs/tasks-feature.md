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
("completed"/"redo"), `redoReason`, `reviewedBy/At`, `managerDownloadedAt`.

Rules (docs/reference/firestore.rules.deployed — **redeploy after changes**):
staff can only write completions as themselves and cannot overwrite another
staff member's completion; tasks are manager-write-only.

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

- Uploads are compressed to **≤ 2 MB** (`Services/ImageCompressor.swift`:
  downscale to 1600 px + stepped JPEG quality).
- Photos live only in the app sandbox (`Services/TaskPhotoCache.swift`),
  never the phone photo library.
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
