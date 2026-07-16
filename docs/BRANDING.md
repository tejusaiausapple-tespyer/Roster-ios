# Branding & Product Positioning — Rosterra

## What this project is (current)

**Rosterra is a self-use workforce roster app** — built and operated by **SURA INVESTMENTS PTY LTD** for the owner’s own business / personal project.

It is **not** a commercial SaaS product yet:

| | Current (this build) | Later (planned) |
|---|---|---|
| Model | Single-tenant, self-use | Multi-tenant SaaS |
| Who uses it | The business owner (manager) + their staff | Many customer organisations |
| Who “owns” the tenant | The builder / business owner | Each customer; Super Admin operates platform |
| Manager account | Business-owner account — **not self-deletable** (safety) | Owner/tenant closure via Super Admin |
| Staff accounts | Created and deleted in-app by the manager | Same pattern per tenant |
| Billing / plans | None | Subscriptions / plans (future) |
| Public marketing | Minimal site (privacy, terms, contact) | Full product marketing when SaaS ships |

Use this framing in App Store copy, Review Notes, Privacy/Terms, and internal docs so reviewers and future you don’t treat the app as a marketplace or multi-business platform.

## Product name

**Rosterra** — replaces the working name "Sura Roster".

- Rationale: short brand name with “roster” audible in the root; category is self-evident.
- App Store listing pattern: **Rosterra — Staff Scheduling & Shift Rosters** (name = brand, subtitle = category).
- Legal operator: **SURA INVESTMENTS PTY LTD** (Adelaide / Mount Barker, SA).
- Support: `support@sura-roster.com`
- Site: `https://sura-roster.com`

## How to describe it (copy guidance)

**Do say**
- Invite-only staff scheduling for a workplace
- Manager creates staff accounts; employees sign in with credentials their employer provides
- Self-use / single-organisation deployment for the operator’s business

**Don’t say (yet)**
- “For teams everywhere” / “join thousands of businesses”
- Free trial, pricing tiers, or multi-company signup
- Self-serve business registration or marketplace positioning

Suggested short description for ASC:

> Rosterra is invite-only workforce scheduling for one workplace: rosters, timesheets, leave, and payslips. Staff accounts are created by the manager. There is no public sign-up.

## Pre-launch checks (before first TestFlight / App Store upload)

Even as a self-use app, the App Store listing is public — keep these clean:

- [ ] USPTO / AU trademark search for “Rosterra” (classes 9 & 42) and home-country registry.
- [ ] Domain: sura-roster.com is live; optional brand domains (rosterra.com / .app) if you want them later.
- [ ] App Store search for exact-name conflicts (names must be unique).
- [ ] Companies-register search for the trading/product name if you expand beyond the company name.

## Rename touchpoints (already largely applied)

- `CFBundleDisplayName` → **Rosterra** (`Rosterra/Resources/Info.plist`).
- Bundle ID (locked for shipping): `com.surainvestments.roster` — do not change after first upload.
- App Store Connect: app name **Rosterra**, subtitle **Staff Scheduling & Shift Rosters**.

## App icon

Redesigned July 2026: three staggered shift bars with staff-avatar badges + clock badge, indigo gradient. Generator: `scripts/generate-app-icon.swift`.

iOS 1024 marketing icon must be **opaque** (no alpha) or App Store validation rejects the upload. Verify with `sips -g hasAlpha AppIcon-1024.png` → `hasAlpha: no`.

## Future SaaS (do not implement in this build)

When the project becomes multi-tenant SaaS:

1. Introduce **Super Admin** for tenant/owner lifecycle (including manager/business-owner deletion and org closure).
2. Revisit branding as a commercial product (pricing, signup, marketing site).
3. Update Privacy, Terms, App Review notes, and this file to match the new model.

Until then, keep every user-facing surface honest: **self-use roster app, not a business platform.**
