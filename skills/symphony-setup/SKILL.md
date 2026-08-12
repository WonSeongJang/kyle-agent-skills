---
name: symphony-setup
description: Install or normalize a repository for Symphony. Use when the user wants a repo-local WORKFLOW.md, run-symphony.sh, local .codex skills, or a wait-safe Symphony configuration with gpt-5.4-mini.
---

# Symphony Setup

Use this skill to set up or normalize Symphony inside a repository.

## Use When

- The user wants to install Symphony for a repo or copy an existing Symphony setup into another repo.
- The repo needs a `WORKFLOW.md` contract, `scripts/run-symphony.sh`, repo-local `.codex/skills`, or a safe wait policy.
- The user explicitly wants these four settings preserved:
  - `agent.max_turns: 8`
  - `codex.command` uses `gpt-5.4-mini`
  - `polling.interval_ms: 8000`
  - a `Wait protection` section that stops turns while waiting on human input or review

## Workflow

1. Inspect the repo's current workflow files and package manager.
2. Use the upstream `openai/symphony` repo as the structural reference, but keep paths repo-local.
3. Normalize the repo-specific `WORKFLOW.md`.
   - For Codex app-server, set the model via config form such as `-c model='gpt-5.4-mini'`.
   - Do not rely on `--model gpt-5.4-mini` for app-server runs unless you have verified the installed
     Codex CLI version honors it in session metadata.
4. Refresh `scripts/run-symphony.sh` so it points at the repo's own `WORKFLOW.md`, workspace root, logs, and source repo URL.
5. Copy or update repo-local `.codex/skills` entries for `commit`, `pull`, `push`, `land`, and `linear` when the repo uses Symphony-style flows.
6. Validate with shell syntax checks and `git diff --check`.
7. If the workflow is waiting on human input or review, update the workpad and stop instead of spinning on turns.

## Guardrails

- Do not globalize repo-specific `WORKFLOW.md` settings.
- Do not raise `max_turns` above 8 unless Kyle explicitly asks.
- Do not switch away from `gpt-5.4-mini` unless Kyle explicitly asks.
- Treat Codex app-server model selection as a runtime behavior to verify, not an assumption.
- Keep `polling.interval_ms` at 8000 unless the repo has a stronger reason.
- Treat `Human Review` or explicit waiting as a stop condition, not a loop.
- Update existing Symphony files in place instead of duplicating them.
