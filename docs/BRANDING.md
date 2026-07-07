# Branding & Naming — Decision Log

## Product name (decided 2026-07-05, apply later)

**Rosterra** — replaces the working name "Sura Roster".

- Rationale: Sling-style short brand name, but with "roster" audibly in the root so the category is self-evident. Came up clean in scheduling-industry searches (no existing rostering/scheduling product found under this name as of July 2026).
- App Store listing pattern: **Rosterra — Staff Scheduling & Shift Rosters** (name carries the brand, subtitle carries the category, same model Sling uses).

## Pre-launch checks (do BEFORE first TestFlight/App Store upload)

- [ ] USPTO trademark search (tmsearch.uspto.gov), classes 9 & 42; plus home-country registry.
- [ ] Domain: rosterra.com, or getrosterra.com / rosterra.app fallbacks.
- [ ] App Store + Google Play search for exact-name conflicts (App Store names must be unique).
- [ ] Companies-register search in country of incorporation.

## Rename touchpoints (when applying)

- `CFBundleDisplayName` in `RosterStaff/Resources/Info.plist` — ✅ applied 2026-07-07 (now "Rosterra"). User-facing strings (Face ID / permission prompts, calendar PRODID, `AppSettings.companyName` fallback) also updated.
- `bundleIdPrefix` in `project.yml` (currently `com.sura.roster`).
- `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` for app + tests targets (currently `com.surainvestments.roster`). **Lock this before the first upload — bundle IDs cannot change after shipping.**
- App Store Connect app name + subtitle when the listing is created.

## App icon

Redesigned July 2026: three staggered shift bars with staff-avatar badges + clock badge, indigo gradient. Generator: `scripts/generate-app-icon.swift` (run `swift scripts/generate-app-icon.swift <out-dir>`; renders iOS 1024 + all macOS sizes).
