---
name: md-visual-workflow
description: Turn Markdown ideas, service explanations, user manuals, plain-language glossaries, repo notes, architecture summaries, or codebase explanations into detailed source Markdown, visual-spec JSON, HTML/CSS preview pages, PNG/SVG exports, and optional image-generation prompts. Use when the user wants a Markdown to visual spec to HTML or image loop for service intro decks, feature-by-feature user manuals, beginner-friendly terminology documents, developer handoff maps, proposal visuals, repo understanding, or vibe-coding handoff documentation. Mermaid, C4, and D2 are optional only when a diagram DSL is useful.
---

# MD Visual Workflow

## Why

People often understand an idea or repository only after seeing the flow. This skill keeps Markdown plus `visual-spec.json` as the editable source of truth, then creates quick HTML/CSS previews and optional polished images so the same thinking can be reviewed, submitted, or handed off without losing track of changes.

## Purpose

Use this skill to make a repeatable visual-thinking pipeline:

```text
Markdown source -> visual-spec.json -> HTML/CSS preview -> PNG/SVG export -> optional image generation
```

Prefer exact HTML/CSS or SVG for text-heavy artifacts. Use Mermaid, C4, or D2 only when the task specifically benefits from a diagram DSL. Use image generation only as the final polish layer when typographic accuracy is not critical, or after creating a precise source image.

## Source Detail vs Visual Summary

The canonical Markdown source is the detailed document. The visual spec, HTML preview, and PNG/SVG export are compressed visual summaries.

Apply this to every layer:
- `source.md` or the main Markdown document should explain context, edge cases, examples, and decision rules in detail.
- `visual-spec.json` should extract only the core visual argument, short labels, and the few distinctions the reader must remember.
- `preview.html` and `preview.png` are review and presentation aids, not replacements for the detailed source.

Do not make the HTML/PNG carry every detail. If the subject is complex, keep the nuance in Markdown and make the visual answer: "What is the shape of this?".

## Mode Selection

Choose one mode before producing artifacts.

Default to the **three-layer explanation structure** when explaining a product, service, repository, or vibe-coded app:

```text
1. Service Intro      -> why it exists, who it helps, what changes
2. User Manual        -> what the user sees, clicks, decides, and gets
3. Developer Handoff  -> where the code/data/API pieces live and what to do next
```

Add a fourth glossary layer when the material contains domain jargon, acronyms, manufacturing/logistics terms, legal/finance/medical terms, implementation terms, or any terms a non-specialist reader may not know:

```text
4. Plain-Language Glossary -> terms a general reader may not know, explained with examples and comparisons
```

People understand from big flow to detail. Do not mix all three audiences into one crowded diagram unless the user explicitly wants a single map.

### Service Intro Mode

Use for service overview decks, pitch/proposal visuals, product introductions, landing-page concept visuals, or explaining an idea to someone seeing it for the first time.

Emphasize:
- why the service exists
- target user and pain
- before/after workflow
- service value and expected result
- current status and next milestone only at a high level
- diagrams a non-technical reviewer can understand

Avoid:
- code paths, API names, package versions, storage details, internal TODO ids
- implementation caveats unless they affect user trust or launch readiness

Recommended diagrams:
- problem/solution comparison
- service core flow
- user or stakeholder map
- value cards
- simple current/next timeline

### User Manual Mode

Use for feature-by-feature manuals, product walkthroughs, operator guides, screen-flow explanations, or “how do I use this?” documents.

Emphasize:
- what the user sees first
- what each feature/button/action means
- what decision the user should make
- what result appears after each step
- how one feature leads to the next

Avoid:
- framework names, DB tables, route names, infra, deployment, package versions
- broad product pitch language that does not help usage

Recommended diagrams:
- end-to-end usage flow
- feature cards
- action meaning table/comparison
- before/after result flow
- “remember these rules” cards

### Developer Handoff Mode

Use for explaining a repository, vibe-coded product, architecture, workflow, implementation plan, or handoff for a developer/agent.

Emphasize:
- repo purpose and main user/operator workflows
- module/service boundaries
- data flow and external dependencies
- current feature map and future work
- risk/unknown areas

Recommended diagrams:
- visual system map
- C4 Context and Container diagrams when developer-facing architecture is needed
- data flow
- request/lifecycle flow
- feature map
- agent or automation workflow

Do not perform broad code analysis unless the user asks. If the repo is out of scope or the local instructions forbid code analysis, work from existing docs and user-provided summaries only.

### Plain-Language Glossary Mode

Use for terminology documents, developer handoff support docs, domain onboarding, proposal packages, or any artifact where a reader could get stuck on jargon before understanding the product.

Emphasize:
- terms a general reader may not know, even if they seem obvious to specialists
- acronym expansion and plain Korean explanation
- concrete examples from the product domain
- "do not confuse with" comparisons
- why the term matters in the product or workflow
- implementation criteria only after the easy explanation

For each term, prefer this structure:

```text
Term
- plain meaning
- acronym expansion, if any
- simple analogy
- concrete example
- what it is not
- why it matters here
- product/development rule
```

Include basic industry terms such as SKU, BOM, Variant, LOT, Serial, Revision, Snapshot, Hash, API, DB, ERP, Portal, Resolver, Token, Log, and domain-specific units when they appear in the source. The point is not to list only "advanced" terms; the point is to remove every likely reader blocker.

The glossary source should be much more detailed than the glossary HTML/PNG. The visual summary should show the key term groups and confusing distinctions, not the full dictionary.

### Legacy Idea Mode

Use only when the request does not fit the three-layer structure and is closer to startup ideas, proposals, grant applications, PRDs, business model sketches, or product strategy.

Use for startup ideas, proposals, grant applications, PRDs, service briefs, product strategy, or user workflow explanations.

Emphasize:
- why the idea exists
- target user and pain
- before/after workflow
- free/paid or stakeholder flow
- social value and risk boundaries
- diagrams a non-technical reviewer can understand

Recommended diagrams:
- user journey
- problem/solution flow
- business model flow
- stakeholder map
- optional C4 only when the user wants developer-facing structure

### Legacy Repo Mode

Treat legacy repo mode as Developer Handoff Mode unless the user explicitly asks for a different structure.

## Audience-Layer Mental Model

Use the same pipeline for all modes, but optimize the output for the reader:

- Service intro: help a first-time reader understand why the service matters.
- User manual: help a user operate the service without knowing the implementation.
- Developer handoff: help a developer or future agent understand what exists, how it moves, and where to continue.
- Plain-language glossary: help a non-specialist reader understand the words before evaluating the service, manual, or handoff.

When the user asks for a complete explanation set, produce the three layers as separate folders or artifacts rather than one mixed artifact. If jargon is present, add the glossary as its own source document and/or folder.

## Workflow

### 1. Establish Source Markdown

Find or create the canonical Markdown source first. The user does not need to write `visual-spec.json` manually. If `visual-spec.json` does not exist, create it from the Markdown source or the user's plain-language request.

Start with a short `Why`:

```text
Why: who has what problem, and what becomes easier?
```

For service intro mode, capture:
- one-line service concept
- target users
- current pain
- before/after
- service workflow
- core value
- current/next status

For user manual mode, capture:
- primary user goal
- first screen/start point
- feature sequence
- action labels and meanings
- outputs/results
- what to do next

For developer handoff mode, capture:
- repo purpose
- user/operator workflows
- main modules
- external systems
- build/deploy/automation notes
- unresolved risks

For plain-language glossary mode, capture:
- all visible jargon and acronyms from the source
- common industry terms a general reader may not know
- similar terms that may be confused with each other
- simple examples using the same product or workflow
- product/development rules attached to each term

For legacy idea mode, capture:
- one-line concept
- target users
- current pain
- service workflow
- monetization
- social value
- image candidates

If the user does not know what to write, ask for or infer only the minimum:
- what visual is needed
- who will read it
- the one message it should communicate
- rough steps, cards, or comparison points

Do not block on a perfect brief. Create a first visual spec and iterate from the preview.

### 2. Create `visual-spec.json`

Create a structured visual specification before drawing. This is the bridge between rough Markdown and final HTML/CSS. Treat it as an AI-generated intermediate artifact, not a form the user must fill out.

The visual spec should contain:
- `title`: visible title
- `subtitle`: optional one-line explanation
- `mode`: `service-intro`, `user-manual`, `developer-handoff`, `glossary`, `idea`, or `repo`
- `audience`: who should understand the image
- `message`: the one point the image must communicate
- `theme`: optional colors and tone
- `sections`: visual blocks such as `flow`, `cards`, `comparison`, `lanes`, or `timeline`
- `notes`: source assumptions or QA reminders that should not necessarily appear in the image

When source material is thin, create a minimal spec with only `title`, `mode`, `audience`, `message`, and one `sections` entry. Add more structure after the first preview.

Keep visible labels short. Put nuance in the Markdown source or `notes`, not inside crowded boxes.

For Korean submission/proposal images:
- avoid jargon in visible labels
- prefer `무료`, `유료`, `검수`, `분석`, `기준표`, `질문 리스트`
- avoid labels that imply regulated recommendations unless the user explicitly accepts the risk
- use exact text source for image-generation prompts to reduce typos

For user-manual images:
- use labels that match what the user sees or does
- describe action meanings in plain language
- avoid internal implementation names
- keep “what happens next” visible

For developer-handoff images:
- make boundaries explicit
- show current vs pending work
- separate product behavior from technical implementation
- surface risks without burying the main flow

For glossary images:
- show the 4-8 terms or term groups that unblock understanding first
- use plain labels such as `판매 코드`, `재료표`, `제품 변형`, `생산 묶음`, `확정본`
- compare confusing terms directly, such as `SKU vs Product Case`, `Option vs Variant`, `LOT vs Serial`, `Draft vs Snapshot`
- keep the full explanations in Markdown, not in crowded cards

See `references/patterns.md` for reusable visual-spec templates and optional Mermaid/C4/D2 patterns.

### 3. Build HTML Preview

Use `scripts/render_visual_spec_html.py` for a fast local preview from visual spec:

```bash
python3 <skill>/scripts/render_visual_spec_html.py \
  --input visual-spec.json \
  --output exports/visual-preview.html
```

Use `scripts/build_visual_html.py` only when the user already has Markdown with Mermaid blocks and wants a quick document preview:

```bash
python3 <skill>/scripts/build_visual_html.py \
  --input source.md \
  --output exports/source-preview.html \
  --title "Readable title" \
  --mode idea
```

The generated HTML renders Markdown sections and Mermaid blocks in a clean single-page preview. Open it in a browser or screenshot it for quick review.

Use HTML preview before image generation when:
- the diagram has Korean text
- the user wants to inspect flow before spending time on polished generation
- the diagram may need several wording iterations

Treat HTML preview as the fast loop. Treat image generation as the slow polish loop.

### 4. Export Image

Preferred order:

1. Create exact SVG/HTML when text accuracy matters.
2. Export/screenshot to PNG.
3. Only then use image generation as a polish layer if needed.

For image generation prompts, include:
- exact diagram title
- exact card labels
- exact body copy
- visual style constraints
- instruction to avoid extra text
- warning that Korean text must be accurate

After generation, always visually inspect for:
- typos
- truncated text
- wrong arrows
- missing free/paid labels
- text-image mismatch with the source Markdown

If generated text is wrong, regenerate or fall back to the SVG/HTML source image.

Do not use an AI-generated bitmap as the only source for a text-heavy diagram. Keep the Markdown and `visual-spec.json` source beside it.
Do not use Mermaid as a default step for proposal infographics or BM flows. HTML/CSS from visual spec is the default.

### 5. Deliver Artifacts

Return the source and export paths:

```text
source.md
visual-spec.json
preview.html
preview.png or preview.svg
optional generated image path
```

For complete explanation sets, include each layer's source and exports. If a glossary was created, clearly identify that the glossary Markdown is the detailed reference and the glossary HTML/PNG is a summary visual.

When the user is submitting a form, do not submit it unless explicitly asked.

## Quality Checklist

- The visible image matches the Markdown source.
- The diagram has one clear message.
- Free/paid, user/operator, or before/after boundaries are visually distinct.
- Idea-mode diagrams are understandable without engineering context.
- User-manual diagrams explain what the user sees, clicks, decides, and receives.
- Developer-handoff diagrams are useful to a developer continuing the work.
- Glossary Markdown explains every likely non-specialist blocker, including basic acronyms and industry terms.
- Glossary visuals summarize the key term groups and confusing distinctions without pretending to replace the detailed glossary.
- Text-heavy outputs have an exact HTML/SVG fallback.
- Generated images are inspected for typos before use.
- Mermaid/C4/D2 are used only when they simplify the output, not as a required pipeline step.
