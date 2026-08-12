---
name: admin-dashboard-playbook
description: Decide and design an internal admin dashboard for a web service. Use when the user wants a reusable admin dashboard kit, needs to determine whether Search Console alone is enough or an internal dashboard is required, or wants guidance for implementation surface, validation, UTM attribution, and short share links across projects.
---

# Admin Dashboard Playbook

Use this skill to decide whether a service needs an internal admin dashboard, and if so, how to structure it so it can be reused across projects.

## Use This Skill When

- The user wants a reusable admin dashboard kit.
- The user asks whether Search Console is enough or a custom dashboard is needed.
- The user wants a project-agnostic dashboard playbook.
- The user wants dashboard docs to include UTM, channel attribution, CSV import, and validation.

## Workflow

### 1. Decide the smallest viable level

Read `references/decision-matrix.md`.

Choose one:

- Search Console only
- Search Console + internal behavior dashboard
- Search Console + full operations dashboard

Do not assume every service needs a full admin console.

### 2. Define the common dashboard core

Read `references/common-guide.md`.

Use it to define:

- core questions the dashboard must answer
- required tabs
- service-type substitutions
- minimum operating cutline

### 3. Map the implementation surface

Read `references/implementation-surface.md`.

Use it to decide:

- required files
- event schema
- DB objects
- environment variables
- admin auth shape

### 4. Add channel attribution and sharing rules

Read `references/utm-share-links.md`.

If the service needs non-Google attribution:

- define `source / medium / campaign`
- define short redirect links like `/go/...`
- ensure the dashboard shows traffic breakdown at that level

### 5. Validate the system end to end

Read `references/validation-checklist.md`.

Minimum validation:

- auth works
- events store correctly
- traffic breakdown renders
- Search Console CSV import works if used
- CSV export works

## Output Expectations

When using this skill, produce:

1. decision level
2. dashboard scope
3. implementation surface
4. validation checklist
5. UTM/share-link plan if needed

## References

- `references/decision-matrix.md`
- `references/common-guide.md`
- `references/implementation-surface.md`
- `references/validation-checklist.md`
- `references/utm-share-links.md`
