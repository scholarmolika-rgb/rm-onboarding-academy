# RM Academy

The design system for the RM Onboarding Academy: the 30-day platform that takes a new corporate Relationship Manager from Day 1 to certified. It serves five audiences on the same screens (trainee, mentor, reporting manager, HR partner, bank leadership), so it is quiet, dense and exact. One ink-blue accent, neutral greys biased toward that blue, and three semantic colours that only ever mean a state.

## Principles
1. **Calm over loud.** A bank's people judge a tool by how trustworthy it looks. No gradients, no emoji, no decorative colour. `accent` appears only where something is actionable or selected.
2. **State is visible at a glance.** Every trainee, escalation and gate carries a status pill. `good` = cleared, `warn` = gate/coaching/watch, `crit` = fail/repeat/breach. Semantic colour never doubles as brand colour.
3. **Borders, not shadows.** Panels are `surface` with a `line` border and `radius-lg`. Shadow (`shadow-float`) is reserved for layers that float above the page.
4. **Numbers are data.** KPI values use the `stat` style with tabular numerals; money is written in Indian units (₹ lakh, ₹ Cr) and never mixed in one table.
5. **Privacy in the UI.** Never render a customer name, PAN, Aadhaar or account number. Shadow logs show masked references in the `code` style.

## Content fundamentals
- Write from the user's side: "Record decision", "Mark refresher complete", not system words like "submit payload".
- Titles are plain nouns or a direct question: "Coaching queue", "What structured onboarding is worth".
- Supportive tone with trainees ("Your coaching sessions are scheduled"), direct tone with coaches and HR ("Action required: 1-day coaching for …").
- Scores never appear in email subject lines or push notifications.
- Use the programme's own vocabulary consistently: *Gate 1 (Day 15, 80%)*, *Gate 2 (Day 21, 75%)*, *Certification (Day 30)*, *coaching day*, *refresher*, *shadow day*, *sign-off*.

## Visual foundations
- **Colour:** light and dark themes, identical token names. Text colours meet 4.5:1 on `surface` and `surface-bg` in both themes; `text-faint` is for non-essential meta only.
- **Type:** `display` (Source Serif 4) for page and section titles only; `body` (IBM Plex Sans) for everything else; `mono` (IBM Plex Mono) for codes and addresses. Eyebrows are uppercase with 0.08em tracking.
- **Spacing:** 4px base (`space-1` … `space-7`). Panels pad `space-5`; grids gap `space-4`; page gutter never below `space-4`.
- **Radius:** `radius-sm` day cells and tags, `radius-md` controls, `radius-lg` panels, `radius-pill` status and chips.
- **Layout:** a 232px left rail of role views on desktop that becomes top tabs under 760px; content in 4-, 3- or 2-column grids that collapse to one column on phones.

## Signature element: the 30-day strip
Thirty cells, one per training day, in three phases (15 / 6 / 9). Completed days fill with `accent`, today is outlined in `accent`, gate days (15, 21, 30) use `warn-soft` until cleared, then `good`. Use it anywhere a person's position in the programme matters.

## Iconography
No icon set is required. Status is carried by pills (a 6px dot in `currentColor` plus a label). If icons are added later, use a single-weight 1.5px outline set, `text-muted` by default and `accent` when interactive.

## Accessibility
Focus ring: 2px `accent` outline with 2px offset on every interactive element. Checkboxes and radios use `accent-color: accent`. Motion is limited to bar width transitions and is disabled under `prefers-reduced-motion`.

## Files in this folder
- `tokens.json` — every colour (light + dark), type style, spacing, radius and shadow token with usage notes.
- `components.css` — ready-to-use classes: `ds-btn`, `ds-pill--good|warn|crit|info|mute`, `ds-panel`, `ds-stat`, `ds-strip`/`ds-day`, `ds-callout`, `ds-bar`, `ds-textarea`. They read CSS variables named after the tokens (`--accent`, `--surface`, `--space-4`, `--radius-md`, `--font-body` …).
- `components/*.md` — guidelines for each component.
The live, browsable version of this system is published as the "RM Academy" design system artifact.
