# Classification Guide

Use this file to decide whether the issue is local or foundational.

## Treat as a one-off screen bug when

- the problem is tied to one component's content
- the bug is caused by a single layout exception
- no shared overlay/viewport behavior is involved

Examples:

- one card has the wrong padding
- one button label wraps oddly
- one page uses the wrong icon

## Treat as a shared foundation issue when

- the same class of problem can recur on many screens
- the issue touches overlay behavior
- the issue involves browser viewport, not just one card
- the bug is about stacking, focus, or scroll behavior

Examples:

- modal is not centered
- backdrop stops at the container width
- body scroll moves while modal is open
- dropdown appears below sticky header
- sheet/drawer safe-area spacing is inconsistent

## Strong foundation signals

If two or more are true, treat it as foundation by default.

1. Uses `fixed`, `absolute`, `portal`, `z-index`, or `overflow`
2. Affects modal/sheet/drawer/dropdown/toast/loading overlay
3. Breaks differently on mobile vs desktop
4. Needs the same change in several components
5. Would likely regress when a new overlay is added later

## Rule of thumb

If the problem is about how UI floats above the page, it is usually a foundation problem.
