# Validation Checklist

Use this checklist after changing frontend foundations.

## Minimum checks

1. Component or focused test passes
2. Typecheck passes
3. Build passes
4. Real browser smoke test passes

## Browser checks for overlays

- dialog appears in the visual center of the viewport
- backdrop covers the full viewport
- background scroll is locked while open
- background scroll is restored after close
- close button works
- outside click works if intended
- ESC works if intended
- sticky header does not overlap the dialog
- mobile width and spacing look natural
- mobile does not get stuck after the modal closes

## Browser checks for SPA screen transitions

- scroll down on screen A
- move to screen B
- confirm screen B starts at the top when it is a new screen
- if browser back/forward behavior is special, verify that separately instead of assuming it matches forward navigation

## Representative flows

Prefer checking one real flow such as:

- result card -> save -> login modal
- share button -> share modal
- preflight -> confirm -> close
- options screen -> list screen

If a mobile issue is suspected, explicitly validate:

- open modal
- close modal
- scroll page again

Do not stop at “the modal opened correctly”.

## Documentation checks

- if the rule is now shared, update the guideline doc
- if production behavior changed, update changelog
