# Rosterra

Native iOS app for staff rostering, shift management, timesheet submission, and task tracking. Built for Sura Investments Pty Ltd.

---

## What It Does

Rosterra is a two-role workforce management app:

**For Staff (Employees):**
- View assigned shifts on a weekly roster
- Submit worked hours after shifts end
- Report absences
- Manage weekly availability
- Complete assigned tasks with photo evidence
- Receive notifications from management

**For Managers:**
- Create, edit, and publish shift rosters
- Approve or reject staff timesheets
- View real-time dashboard with today's metrics
- Monitor task completion logs

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Platform | iOS 17.0+ (iPhone, iPad, Mac Catalyst) |
| Language | Swift 5.0 |
| UI Framework | SwiftUI |
| Backend Auth | Firebase Authentication |
| Database | Cloud Firestore (real-time listeners) |
| Storage | Firebase Storage (task photos) |
| API | Cloudflare Worker (`sura-roster.com`) |
| Build | Xcode + XcodeGen |
| Packages | Swift Package Manager |

---

## Project Structure

```
Rosterra/
├── App/                    # Entry point, AppDelegate, RootView
├── Models/                 # Data models (Shift, Timesheet, User, etc.)
├── Services/               # Firebase, Auth, API, Calendar services
├── ViewModels/             # AuthViewModel, AppRouter
├── Features/
│   ├── Auth/               # Login, password change, profile completion
│   ├── Home/               # Staff home dashboard
│   ├── Roster/             # Staff roster view
│   ├── Tasks/              # Staff task completion
│   ├── History/            # Timesheet history
│   ├── Availability/       # Weekly availability management
│   ├── Account/            # Profile & settings
│   ├── Shell/              # Staff tab bar
│   ├── Shared/             # Reusable components (ShiftCard, sheets)
│   └── Manager/            # All manager-side views
│       ├── Dashboard/
│       ├── Roster/
│       ├── Timesheets/
│       └── Shell/
├── DesignSystem/           # Theme + reusable UI components
└── Resources/              # Assets, plists, entitlements
```

---

## Setup

### Prerequisites

- macOS with Xcode 15+
- Firebase project (Auth + Firestore + Storage)
- `GoogleService-Info.plist` from Firebase Console

### Steps

1. Clone the repository
2. Place `GoogleService-Info.plist` in `Rosterra/Resources/`
3. Open `Rosterra.xcodeproj` in Xcode
4. Wait for SPM to resolve dependencies (Firebase SDK)
5. Build and run on simulator or device

### XcodeGen (optional)

If modifying `project.yml`:
```bash
brew install xcodegen
xcodegen generate
```

---

## Configuration

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project definition (targets, dependencies, settings) |
| `Resources/GoogleService-Info.plist` | Firebase configuration (gitignored) |
| `Resources/Info.plist` | iOS app metadata (display name, permissions) |
| `Resources/Rosterra.entitlements` | Associated domains, capabilities |
| `Services/AppConfig.swift` | API URL, relying party, timeouts |

---

## Key Architecture Decisions

- **Single codebase, two roles** — Routes to Staff or Manager UI based on user's `role` field in Firestore
- **Real-time by default** — All data uses Firestore `onSnapshot` listeners, no polling
- **RosterRepository as single source** — One `@Observable` class holds all app state via SwiftUI environment
- **Australia/Adelaide timezone** — All date logic is timezone-aware via `RosterCalendar`
- **Monday-start weeks** — ISO 8601 week format throughout
- **Offline capable** — Firestore persistence cache enabled by default

---

## Documentation

| Document | Description |
|----------|-------------|
| [`docs/agents.md`](docs/agents.md) | **AI agent context** — comprehensive reference for AI models working on this project |
| [`docs/staff-guide.md`](docs/staff-guide.md) | Staff-side feature documentation |
| [`docs/manager-guide.md`](docs/manager-guide.md) | Manager-side feature documentation |
| [`docs/architecture.md`](docs/architecture.md) | How staff and manager sides connect |
| [`docs/WHEN_DEVELOPER_ACCOUNT_READY.md`](docs/WHEN_DEVELOPER_ACCOUNT_READY.md) | Push notification setup checklist |
| [`docs/smoke-test.md`](docs/smoke-test.md) | Manual regression checklist — run before merging any change |

---

## Current Status

### ✅ Implemented
- Email/password authentication with biometric quick-login
- Staff shift viewing with week navigation
- Timesheet submission and resubmission
- Absence reporting
- Weekly availability management
- Task completion with camera photo evidence
- Notification messages display
- Timesheet history with filters
- Calendar integration (EventKit + ICS fallback)
- Manager dashboard with live metrics
- Manager shift CRUD (create, edit, delete, publish) with iPad/Mac week-grid, drag move/copy, bulk delete
- Manager timesheet approval/rejection (week-based review)
- Manager staff directory with per-field editing, email-change requests, address re-entry requests
- Manager availability overview (staff × 7-day matrix)
- Manager weekly reports (hours, labour cost, per-staff breakdown)
- Device authentication gate (Face ID / Touch ID / passcode)
- Forced password change flow
- Profile completion enforcement
- iPad/Mac adaptive layouts (sidebar + width-driven grids, Liquid Glass on iOS 26+)
- Push notifications (paid team wired 2026-07-15; APNs → FCM → Firestore end-to-end)

### 🚧 Planned
- Manager task management UI (placeholder tab)
- Manager tenure & hours view (placeholder tab)
- Manager wage/payroll view (placeholder tab)
- Passkey authentication flow (service code exists; registration not wired)

---

## For AI Agents

If you're an AI model working on this project, **start by reading [`docs/agents.md`](docs/agents.md)**. It contains complete file references, data flow diagrams, Firestore schemas, business rules, modification guides, and coding conventions.

**Always update `docs/agents.md` when making structural changes.**

---

## License

Proprietary — Sura Investments Pty Ltd. All rights reserved.
