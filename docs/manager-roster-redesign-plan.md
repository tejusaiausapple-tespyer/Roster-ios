# Plan — Manager Roster Tab Redesign (iPad & macOS, 2026 Liquid Glass)

> Status: **COMPLETED** (shipped with Option A availability gating — see `ManagerRosterView` and the Theme glass helpers). Kept for historical reference; the checklist in §7 is done.
> Scope: `Features/Manager/Roster/ManagerRosterView.swift` (+ small additions to `DesignSystem`). No data-layer changes. iPhone/compact design is preserved (user is happy with it).
> Author: AI agent, 2026-07-03.

---

## 1. Goals

1. Make the Manager → Roster tab feel **smooth and native on iPad and macOS** (fullscreen, portrait, Split View ½ & ⅓, Slide Over, and resized Mac windows).
2. Adopt the **latest 2026 UI (Liquid Glass)** on the navigation layer, correctly and sparingly, per Apple HIG.
3. Preserve all existing behavior: week navigation, filters, drag-to-move/copy, context menus, copy-last-week, publish-week, add-shift, week bounds, metrics.
4. Keep the iPhone/compact layout the user already likes.

---

## 2. Research Findings (grounding the design)

### 2.1 Adaptive layout
- `horizontalSizeClass` alone is **insufficient**: iPad in ⅓ Split View / Slide Over reports `.compact` (same as iPhone), while iPad fullscreen and Mac report `.regular`. Decisions must be driven by **actual container width**, not device.
- Best practice: **branch once at the root** into a layout mode, then let sub-layouts fit (`ViewThatFits`, width-driven column counts).
- **Cap content width** on very wide displays and center it; otherwise a 7-column grid stretches into sparse boxes.
- **Grids respond to space**: keep a comfortable minimum column width; scroll horizontally rather than squishing.

### 2.2 Liquid Glass (iOS/iPadOS/macOS 26)
- Liquid Glass is a translucent, dynamic material for the **navigation layer that floats above content**. Apple guidance: **never apply glass to the content layer** (lists, cards, the grid itself).
- Core APIs: `glassEffect(_:in:)`, `Glass.regular/.clear/.identity`, `.tint(_:)`, `.interactive()`, `GlassEffectContainer`, `.glassEffectID`, button styles `.glass` / `.glassProminent`, `ToolbarSpacer`, `.tabViewBottomAccessory`.
- **Free wins**: recompiling with Xcode 26 auto-applies glass to `NavigationStack` toolbars, the `TabView` tab bar, and the `NavigationSplitView` sidebar — no code changes.
- **Performance**: wrap multiple glass elements in a single `GlassEffectContainer` (glass can't sample glass); avoid glass-on-glass; let glass rest (no continuous animations).
- **Accessibility**: the system handles Reduce Transparency / Increase Contrast / Reduce Motion automatically — do not override. Still respect `accessibilityReduceMotion` for our own drag animations.
- **Availability**: all glass APIs are iOS 26.0+. Must be gated with `if #available(iOS 26.0, *)` + fallback, or the deployment target bumped.

---

## 3. KEY DECISION NEEDED — iOS 26 availability strategy

The project deploys to **iOS 17.0**. Two options:

- **Option A (recommended): Availability-gated adoption.**
  Add a small `glassCapsule()/glassButton()` helper in the DesignSystem that uses real `glassEffect`/`.buttonStyle(.glass)` on iOS 26+, and falls back to the current `.ultraThinMaterial` + Theme surfaces on iOS 17–25. Keeps all existing users; adopts the 2026 look automatically on 26+ devices/Mac.
  - Pros: no users dropped; future-proof; single code path via helper.
  - Cons: a bit more code (the fallback branch).

- **Option B: Bump deployment target to iOS 26.**
  Simplest code, full glass everywhere, but **drops every device/OS below 26** (most of the current user base today). Not recommended for a shipping staff app.

**This plan assumes Option A** unless you choose B. The only difference is whether we write fallbacks; the layout work is identical.

---

## 4. Where glass is applied (and where it is NOT)

| Element | Glass? | Treatment |
|---|---|---|
| NavigationStack toolbar (title pill, etc.) | ✅ Automatic | Free with Xcode 26; keep `ScreenTitlePill` but let bar go glass |
| Manager tab bar / split sidebar (in `ManagerMainView`) | ✅ Automatic | Free; no change here |
| Week-nav + filter control cluster (top bar) | ✅ Yes | `GlassEffectContainer` with `.glass` chips/buttons |
| "Add shift" primary button | ✅ Yes | `.buttonStyle(.glassProminent).tint(Theme.brand)` |
| Per-day "+" buttons in column headers | ✅ Small | `.glass` circular, or plain on fallback |
| Bottom metrics bar | ✅ Yes | Glass bar via `.safeAreaInset(edge: .bottom)` |
| **Shift cards** | ❌ No | Content layer — stay solid `Theme.card` (readability, HIG) |
| **Grid columns / day background** | ❌ No | Content layer — solid surfaces |
| Empty-state card | ❌ No | Content layer |

Rationale: glass on the floating controls = the 2026 look; solid cards for the schedule = legibility and correct hierarchy.

---

## 5. Layout Architecture

### 5.1 One decision at the root (width-driven)
Wrap the roster body in a `GeometryReader` and compute a mode from measured width:

```
enum RosterLayoutMode { case agenda, weekGrid }

// width < ~720  -> .agenda  (reuse the liked iPhone list + WeekSelector)
// width >= ~720 -> .weekGrid (redesigned scheduler)
```

This makes iPad ⅓-split / Slide Over reuse the good compact design, and Mac window-resizing switch smoothly — no reliance on size class alone.

> Note: `ManagerRosterView` is already inside `ManagerMainView`'s `NavigationSplitView` detail on iPad/Mac. We must **not** nest another `NavigationSplitView` — we improve the single scheduler pane.

### 5.2 Week-grid mode
- Centered **max content width** (~1400pt) so ultra-wide Mac windows don't stretch.
- **Min column width** ~160pt. If `7 × 160 + gutters` fits → 7 equal columns. If not → wrap the grid in a horizontal `ScrollView` so days stay readable.
- **Shared vertical scroll** with a **pinned day-header row** (`.safeAreaInset` / pinned section header) so all columns scroll together and headers stay put.
- Fix timezone bug: use `RosterCalendar.calendar` (Adelaide) for the day number instead of `Calendar.current`.

---

## 6. Component-by-component redesign

### 6.1 Top control bar (replaces `pwaTitleActionsPanel`)
- `GlassEffectContainer` holding: week-nav pill (‹ · This week · ›), the date range, then filter chips and actions.
- Reflow with `ViewThatFits`:
  - **Wide**: one row — `[‹ This week ›  date range]  ……  [Staff] [Status] [⋯]  [Add shift]`.
  - **Medium**: two rows — row 1 nav + date + Add shift; row 2 filter chips + ⋯ menu.
- Filter chips show fixed labels ("Staff", "Status") with an **active-state highlight/badge** instead of expanding to the full staff name (`.lineLimit(1)` + max width as backstop). This is the current overflow culprit.
- Buttons: `.buttonStyle(.glass)` for filters/⋯, `.glassProminent` for Add shift (iOS 26+); fallback = current Theme-styled buttons.
- Use `ToolbarSpacer`/`Spacer` for spacing.

### 6.2 Week grid (replaces `pwaRosterGrid`)
- Day-header row: weekday short name, day number (Adelaide TZ), today highlight, shift count, per-day glass "+".
- One vertical `ScrollView`; each day is a column `VStack` of cards; headers pinned above.
- Min-width + horizontal-scroll fallback as in §5.2.
- Keep `.draggable(shift.id)` + `.dropDestination` and the context menu (Edit / Publish / Delete). Wrap the drag highlight animation in a reduce-motion check.

### 6.3 Shift card (`pwaShiftCard`) — content, NOT glass
- Solid `Theme.card`, min height, clearer hierarchy: initials avatar, name (1 line), time range, hours, status dot; dashed border for drafts; subtle approved tint. Comfortable at ~160–200pt width.

### 6.4 Bottom metrics bar (replaces `pwaStatusBar`)
- Move into `.safeAreaInset(edge: .bottom)` as a **glass bar** (iOS 26+) / solid bar (fallback).
- Replace the single bullet-separated line with compact **metric chips** (Hours, Staff, Drafts, Gross, Total inc. Super) that wrap via `ViewThatFits` so they never overflow.

### 6.5 Agenda mode (compact)
- Unchanged design (user likes it), but now also serves narrow iPad contexts. The floating "Add" FAB becomes `.glassProminent` on iOS 26+.

### 6.6 DesignSystem additions
- `Theme.maxContentWidth: CGFloat = 1400`, `Theme.minColumnWidth: CGFloat = 160`.
- A `View.glassContainerCapsule(...)` / `Button.glassAction(...)` helper that gates iOS 26 glass vs. fallback (`.ultraThinMaterial` + Theme surfaces). Centralizes the availability check so call sites stay clean and other screens can reuse it later.

---

## 7. Phased implementation & checklist

- [ ] **Phase 0** — Confirm §3 decision (A or B). If A, add the glass helper + Theme constants.
- [ ] **Phase 1** — Width-driven `RosterLayoutMode` (GeometryReader), max-width container, timezone fix. (Structural, low risk.)
- [ ] **Phase 2** — Rebuild top control bar (ViewThatFits reflow + compact filter chips + glass).
- [ ] **Phase 3** — Rebuild week grid (pinned headers, shared scroll, min-width + horizontal-scroll fallback, better headers). Preserve drag/drop + context menus.
- [ ] **Phase 4** — Redesign shift card (solid, clearer hierarchy).
- [ ] **Phase 5** — Bottom metrics bar as wrapping glass chips via `.safeAreaInset`.
- [ ] **Phase 6** — Polish: reduce-motion, accessibility labels, tokens, glass tuning.

Suggested delivery: Phases 1–3 first → review with user → Phases 4–6.

---

## 8. Verification / testing

- **Build** for iOS Simulator **and** Mac Catalyst.
- **SwiftUI Previews** at fixed widths to simulate every context:
  - iPad portrait 834, landscape 1194 & 1366, ½-split ~678, ⅓-split ~320, Slide Over ~320, narrow Mac ~700, wide Mac ~1800.
  - Light + dark; Dynamic Type XL; Reduce Motion on.
- **Behavior parity** pass: create/edit/delete, drag move+copy, filters (staff/status), copy-last-week, publish-week, week bounds min/max, empty states.
- If iOS 26 simulator available, verify real glass; otherwise verify the fallback path renders correctly on iOS 17.

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Glass APIs unavailable on iOS 17 | Option A availability gating with `.ultraThinMaterial` fallback |
| Xcode < 26 in build env (no glass compile) | Helper compiles both branches; `#available` guards runtime; if SDK lacks symbols, gate with `#if canImport`/compiler check |
| Nested split views on iPad | Keep single scheduler pane; no new `NavigationSplitView` |
| Drag/drop regressions during grid rewrite | Keep `.draggable`/`.dropDestination` contracts identical; test move+copy explicitly |
| Filter-by-name brittleness (existing) | Out of scope for UI; note for later (filter by staff id) |
| Performance of glass on older devices | Single `GlassEffectContainer`; no continuous animations |

---

## 10. Out of scope
- Data-layer / Firestore changes.
- iPhone/compact visual redesign (kept as-is).
- Other manager tabs (Dashboard, Timesheets) — could follow the same glass helper later.
