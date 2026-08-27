---
name: growth-tracking-playbook
description: Design and implement lightweight growth tracking for web services. Use when the user wants Google Search Console setup, self-hosted internal analytics instead of GA, Supabase-backed event tracking, UTM naming rules, short share links such as /go/..., or a reusable attribution/marketing measurement playbook across projects.
---

# Growth Tracking Playbook

Use this skill to set up a practical tracking stack for small and medium web products without overbuilding.

This skill is for deciding and implementing:

- when Search Console alone is enough
- when to add an internal dashboard
- how to structure UTM rules
- how to add short redirect links for sharing
- how to keep privacy boundaries clear

## Use This Skill When

- The user asks how to track inflow, attribution, or channel performance.
- The user wants Search Console, internal analytics, or a lightweight dashboard.
- The user wants UTM conventions or short share links like `/go/...`.
- The user wants a reusable tracking playbook across multiple services.

## Do Not Use This Skill For

- Large enterprise BI design
- Complex ad-platform conversion APIs
- Full product analytics strategy with cohorting, LTV, or warehouse modeling

## Workflow

### 1. Pick the minimum viable tracking level

Start with the smallest setup that answers the user's real question.

- If the question is only `How do people find us from Google?`
  Read `references/decision-matrix.md` and choose `Search Console only`.
- If the question is also `What do users do after landing?`
  Choose `Search Console + internal dashboard`.
- If the question includes `How do shared links from KakaoTalk/blog/X/community perform?`
  Add `UTM + short redirect links`.

Do not add a dashboard just because it sounds sophisticated. Add it when internal behavior or non-Google attribution actually matters.

### 2. Define the implementation surface

Read `references/implementation-surface.md`.

Use it to decide:

- required files
- event schema
- DB objects
- admin dashboard sections
- environment variables

Prefer lightweight primitives:

- Search Console for Google search inflow
- internal event collector for behavior tracking
- Supabase for remote event storage
- Netlify redirects or equivalent for short links

### 3. Define UTM and short-link rules

Read `references/utm-and-go-links.md`.

Keep the rules small and stable:

- `source` for channel name
- `medium` for traffic type
- `campaign` for experiment bundle

When reading or implementing attribution:

- prefer `utm_source` over referrer-derived guesses
- if both UTM and usable referrer are missing, label the bucket `unknown` rather than `direct`
- normalize well-known platform host variants such as `www.youtube.com`/`m.youtube.com`/`youtu.be`, `l.instagram.com`/`instagr.am`, and `vm.tiktok.com` into canonical sources like `youtube`, `instagram`, and `tiktok`

If the service needs human-friendly share links, add `/go/...` redirects that append UTM in the destination URL.

### 4. Keep privacy boundaries explicit

Never log raw sensitive inputs.

Typical examples to avoid storing:

- passwords
- addresses
- names
- freeform notes
- message bodies

Store only metadata needed for attribution and aggregate behavior.

### 5. Validate end to end

Read `references/validation-checklist.md`.

Minimum validation:

- Search Console property and sitemap are set
- event collector accepts data
- dashboard reads from DB
- UTM fields appear in stored events
- `/go/...` links return the intended redirect

## Output Expectations

When using this skill, produce a concrete plan or implementation that includes:

1. chosen tracking level
2. files and systems to add
3. UTM rule table
4. short-link structure if needed
5. environment variable list
6. validation steps

## References

- `references/decision-matrix.md`
- `references/implementation-surface.md`
- `references/utm-and-go-links.md`
- `references/validation-checklist.md`
