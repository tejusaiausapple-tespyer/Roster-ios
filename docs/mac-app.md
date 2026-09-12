# Mac app (`Rosterra/Mac`)

The Mac Catalyst build runs an entirely separate UI layer from iPhone and
iPad. It shares the app's data and business logic and nothing else.

## Redesign pass — 9 September 2026

Implemented persistent page titles, a resizable native split-window sidebar with role-based groups and a pinned account switcher, a responsive dashboard with approvals ahead of charts, and roster controls/totals that remain visible while the schedule scrolls. Week/Day/Staff modes remain available; cards retain readable widths and expose draft drag handles or lock icons.

Only draft shifts can drag in any week. Copy last week now offers all or selected staff, search, a counts preview, duplicate/overlap skipping, and partial-failure reporting. `MacRosterCopyPlan` is shared by preview and commit planning; four Catalyst regression tests exercise publication locking, selection, retries, and overnight overlaps. The commit rechecks repository state for drag actions, but does not introduce server-atomic conflict protection across simultaneous managers.

Validation: signed Catalyst build and four tests passed. Live dashboard, roster, window resizing, and selected-staff copy preview inspected. No shift copy, edit, publish, or delete was committed during visual verification. Further tabs and a persistent shift inspector remain subsequent redesign work.

## Why it is separate

`Rosterra` is one target for all three idioms. Before this rebuild, Mac ran the
same SwiftUI views as iPhone with `#if targetEnvironment(macCatalyst)` patches
sprinkled through them, which is why it read as a widened iPad app.

The split is now at the top of the view tree:

```
RosterraApp
├── #if macCatalyst → MacRootView   (Rosterra/Mac)
└── #else           → RootView      (Rosterra/Features)
```

Every file under `Rosterra/Mac` is wrapped in
`#if targetEnvironment(macCatalyst)`, so the Mac layer contributes nothing to
an iPhone or iPad build, and `Rosterra/Features` is untouched by Mac work.

## What is shared

| Layer | Shared? |
|-------|---------|
| `Models/` | Yes — unchanged |
| `Services/` (`RosterRepository`, auth, Firestore, payroll maths) | Yes — unchanged |
| `ViewModels/AppRouter`, `AuthViewModel`, `AppRoute` | Yes — unchanged |
| `Features/` (iPhone + iPad views) | No — Mac never touches these |
| `DesignSystem/Theme` | No — Mac has its own tokens |

Two shared pieces of logic are deliberately *not* re-implemented on Mac, so the
two apps can't diverge on them:

- **`AppRoute.determine`** — the gate order (setup → restoring → login →
  forced password change → profile completion → device auth → main). Unit
  tested once, used by both roots.
- **`BusinessRules`** — shift status, submit/absence eligibility, week locks,
  payroll gaps, password rules.

## Structure

```
Rosterra/Mac/
├── MacRootView.swift          Gate routing (delegates to AppRoute)
├── Design/
│   ├── MacTheme.swift         MacColor / MacSpace / MacRadius / MacType / MacMotion
│   └── Components/            Surfaces, controls, badges, states, table, feedback, screen
├── Shell/
│   ├── MacNavigation.swift    MacDestination + MacNavigationModel
│   ├── MacSidebar.swift       Source list
│   ├── MacShellView.swift     NavigationSplitView host + sidebar badges
│   ├── MacCommands.swift      Menu bar
│   └── MacWindow.swift        Titlebar, size restrictions, menu notifications
├── ViewModels/                Per-screen state (roster)
└── Screens/                   Auth, Staff, Manager, Account
```

## Conventions

- **Screens** are built from `MacScreen(title:state:actions:content:)`. It
  supplies the native window title and toolbar actions and renders the shared
  loading / error states.
- **Actions use the unified native toolbar.** The sidebar toggle uses the
  leading navigation placement beside the window controls; page actions use
  the trailing primary-action placement.
- **The window title** comes from `.navigationTitle` and
  `MacWindow.setTitle`, called by `MacScreen`.
- **Tables** use `MacTable`: sortable headers, hover, click to select,
  double-click to open, arrow-key navigation, per-row context menus. Sorting is
  declared with `isSortable` and *performed by the screen*, because only the
  screen knows how to order its own domain.
- **Design tokens only.** No literal colours, font sizes or paddings in a
  screen — `MacColor`, `MacSpace`, `MacRadius`, `MacType`, `MacMotion`.
- **Status colour** is centralised in `MacStatusStyle`; a status never gets
  styled two ways in two places.
- **Destructive actions** go through `MacConfirmation`, which forces a specific
  title, the consequence spelled out, and a verb on the confirm button.
- **Async work** uses `MacAsyncButton` rather than a per-screen `isWorking`.

## Mac-specific behaviour

- **Optimised for Mac.** `UIDesignRequiresCompatibility` is `false` in
  Info.plist, so Catalyst runs at 100% scale in the `.mac` idiom rather than
  the 77% scaled-iPad mode. The type ramp in `MacType` is sized for that.
- **Single window.** `AppRouter.shared` is one weak handle that push taps and
  `surafoster://` links route through, and `RosterRepository` owns one set of
  Firestore listeners. Multi-window would need both to become per-scene first.
- **Push routing still works.** `MacNavigationModel` mirrors `AppRouter`, so a
  notification tap moves the sidebar the same way it moves the phone's tab bar.
- **⌘R replaces pull-to-refresh** (a mouse cannot overscroll). Screens opt in
  with `.onMacRefresh` and show a `MacRefreshButton`.
- **Menu commands** are posted as notifications (`.macNewItem`, `.macRefresh`,
  `.macPreviousPeriod`, …) because the menu lives in the `App` scene, well
  above the screen that responds. Only the visible screen is alive, so exactly
  one listener answers.
- **Clocking in from a Mac records no location fix.** A desk Mac is not where
  someone stands when they arrive, so attendance is written unverified rather
  than falsely verified.
- **Photo evidence uses `PhotosPicker`**, not the camera.
- **Payslip export uses `.fileExporter`** — a real save panel, not a share
  sheet.

## Screens

| Destination | Role | Shape |
|-------------|------|-------|
| Overview | Staff | Today + clock in/out, jobs, notifications, upcoming |
| Roster | Staff | Week table, submit hours, report absence, calendar export |
| Tasks | Staff | Day's tasks, complete with photo + note |
| Availability | Staff | Week editor with manager/proximity locks |
| History | Staff | All filed timesheets |
| Payslips | Staff | Month list + detail + PDF save panel |
| Dashboard | Manager | Today's metrics, roster table, attention queue |
| Roster | Manager | Week grid with drag move/copy, or sortable list |
| Tasks | Manager | Day table + completion inspector (photos, redo) |
| Timesheets | Manager | Review queue + inspector, bulk approve |
| Availability | Manager | Staff × weekday matrix, week lock |
| Staff | Manager | Directory table + record inspector |
| Tenure & Hours | Manager | Service length and approved hours |
| Reports | Manager | Weekly hours, cost, per-staff breakdown |
| Wage Awards | Manager | Classifications, allowances, awards, assignments |
| Payroll | Manager | Period table + payslip inspector, generate/publish |
| Locations | Manager | Workplace list + geofence map editor |
| Company Details | Manager | Business identity used on payslips |
| Account | Both | Profile, security, preferences, about |
