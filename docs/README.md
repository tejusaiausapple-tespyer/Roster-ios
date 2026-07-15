# Rosterra Documentation

This directory contains all project documentation for the Rosterra iOS app.

---

## Documentation Index

| Document | Audience | Description |
|----------|----------|-------------|
| [`agents.md`](agents.md) | AI Agents | **Start here if you're an AI model.** Complete project context, file reference, schemas, business rules, modification guides. |
| [`staff-guide.md`](staff-guide.md) | Developers | Staff-side feature documentation — all employee-facing screens and flows |
| [`manager-guide.md`](manager-guide.md) | Developers | Manager-side feature documentation — admin screens and approval flows |
| [`architecture.md`](architecture.md) | Developers | How staff and manager sides connect — shared services, data flow, real-time sync |
| [`WHEN_DEVELOPER_ACCOUNT_READY.md`](WHEN_DEVELOPER_ACCOUNT_READY.md) | Setup | Push notification enablement checklist (waiting for Apple Developer account) |
| [`smoke-test.md`](smoke-test.md) | QA | Manual regression checklist — run before merging any milestone/change |
| [`manager-roster-redesign-plan.md`](manager-roster-redesign-plan.md) | Archive | Completed 2026 roster redesign plan (historical reference) |

---

## Quick Links

- **Root README**: [`../README.md`](../README.md) — Project overview, setup, tech stack
- **Project config**: `../project.yml` — XcodeGen definition
- **App entry**: `../Rosterra/App/RosterraApp.swift`
- **Core data layer**: `../Rosterra/Services/RosterRepository.swift`
- **Business rules**: `../Rosterra/Models/BusinessRules.swift`

---

## Maintenance Rules

1. **AI agents must update `agents.md`** when making structural changes (new features, new files, new collections)
2. Keep feature lists in sync between `staff-guide.md`, `manager-guide.md`, and the root `README.md`
3. Update `architecture.md` when changing how roles interact or when modifying `RosterRepository`
4. The root `README.md` should always reflect the current implementation status
