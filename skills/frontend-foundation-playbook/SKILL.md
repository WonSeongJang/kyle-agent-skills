---
name: frontend-foundation-playbook
description: Decide whether a frontend issue is a one-off screen bug or a shared UI foundation problem, and fix it at the correct layer. Use when modal, overlay, portal, scroll lock, z-index, viewport alignment, sticky header overlap, drawer, dropdown, or loading-block UI behavior is inconsistent or should be standardized app-wide.
---

# Frontend Foundation Playbook

Use this skill when a UI problem looks small on one screen, but is likely caused by a shared frontend primitive.

Typical triggers:

- modal is not centered
- backdrop does not cover the full screen
- background scroll moves while dialog is open
- dropdown/sheet/toast sits under a fixed header
- mobile viewport and safe-area behavior feels inconsistent
- SPA screen changes keep the previous screen's scroll position

## Workflow

### 1. Reproduce in a real browser first

If possible, validate in a browser, not just from a screenshot.

Especially confirm:

- viewport positioning
- backdrop coverage
- background scroll lock
- focus movement
- mobile behavior

### 2. Classify the issue

Read `references/classification.md`.

Decide:

- one-off screen bug
- shared foundation issue

If the problem touches `fixed`, `z-index`, `overflow`, `portal`, `body scroll`, or a repeated overlay pattern, bias toward shared foundation.

### 3. Inventory the affected primitives

Search the codebase for all related UI shells before editing.

Typical searches:

- `Dialog`
- `Modal`
- `Overlay`
- `Portal`
- `fixed inset-0`
- `overflow-hidden`
- `scroll lock`
- `setStep(`
- `scrollTo(`
- `useAppHistorySync`

Do not patch only one screen if multiple variants exist.
Do not sprinkle `scrollTo(0, 0)` across individual screens when the issue is really navigation-wide.

### 4. Fix the base layer first

Prefer:

- shared shell component
- shared hook
- shared z-index rule
- shared viewport modal wrapper

Avoid repeated per-screen CSS patches unless there is a clear reason.

Important:

- Do not keep multiple independent scroll-lock implementations for overlays.
- If `ViewportModal`, `Dialog`, `Sheet`, or loading overlays each lock scroll differently, unify them behind one shared utility first.
- On mobile, prefer `html/body overflow hidden` plus `overscroll-behavior` and `touch-action` control before using `body position: fixed`.

### 5. Backfill representative screens

After the base fix, update the most important consumers together.

Typical order:

- login modal
- save/confirm modal
- share modal
- blocking/preflight modal

### 6. Validate at three levels

Read `references/validation-checklist.md`.

Minimum validation:

1. focused test or component test
2. typecheck/build
3. real browser smoke flow on a representative screen
4. mobile close-and-recover check for scroll behavior
5. if the app is SPA-like, confirm that forward screen transitions reset scroll at the correct layer

### 7. Document the new rule

If the fix changes frontend behavior broadly:

- add or update the project guideline doc
- record it in changelog if production behavior changed

## Output Expectations

When using this skill, produce:

1. classification: one-off vs foundation
2. shared primitive or hook to change
3. affected UI surfaces
4. validation result
5. documentation updates needed

## References

- `references/classification.md`
- `references/validation-checklist.md`
