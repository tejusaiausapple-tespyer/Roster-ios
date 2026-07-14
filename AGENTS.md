# RosterStaff — Session Bootstrap

An AI engineering workspace for this project lives OUTSIDE the repo at
`~/Desktop/RosterStaff-AI/`. It holds process, standards, templates, and
persistent memory. This file only bootstraps it — do not duplicate content here.

## Startup (every session, before any task)
1. Read `~/Desktop/RosterStaff-AI/00-core/AGENT.md` and `00-core/PROJECT_RULES.md`.
2. Read `~/Desktop/RosterStaff-AI/06-memory/MEMORY.md` (owner decisions, constraints, gotchas).
3. Read `docs/agents.md` (code-level truth) and `docs/ROADMAP-PROGRESS.md` (current state).
4. Check git branch/status — if the branch is ⏳ awaiting Sura's device
   verification, don't stack new work on it without asking.

## Hard rules (full list: RosterStaff-AI/00-core/PROJECT_RULES.md)
- Never merge to `main` — Sura merges after verifying on device. Push the branch, hand off.
- Never weaken tests. Run `xcodebuild test -project RosterStaff.xcodeproj -scheme RosterStaff` before handoff.
- All dates via `RosterCalendar` (Australia/Adelaide, Monday weeks); Firestore parsing via `FS` helpers.
- Deployed Firestore rules = `docs/reference/firestore.rules.deployed`; check indexes before compound queries.
- New Swift files → `xcodegen generate` (explicit file refs).
- Keep PWA parity on shared Firestore fields.

## Shutdown (before ending work)
Tests green → self-review (`RosterStaff-AI/04-engineering/REVIEW_GUIDE.md`) →
update `docs/agents.md` + `docs/ROADMAP-PROGRESS.md` + workspace
`06-memory/CHANGELOG.md` (and MEMORY/DECISIONS/TECH_DEBT if applicable) →
write device-verification steps for Sura → push branch, stop.
