# Target Layout

Aim for this structure after setup:

```text
~/.claude/CLAUDE.md
~/.codex/AGENTS.md -> ~/.claude/CLAUDE.md
~/.gjc/agent/AGENTS.md -> ~/.claude/CLAUDE.md

~/.claude/agents/<role>.md
~/.codex/agents/<role>.md
~/.codex/agents/ROUTING.md

~/.claude/skills/<skill-name>/
~/.codex/skills/<skill-name> -> ~/.claude/skills/<skill-name>
~/.gjc/skills/<skill-name> -> ~/.claude/skills/<skill-name>
```

## Meaning

- `~/.claude/CLAUDE.md` is the shared global instruction source.
- `~/.codex/AGENTS.md` and `~/.gjc/agent/AGENTS.md` are compatibility links to that shared source.
- Agent role files may be tool-local even when the global instruction file is shared.
- Shared skills should live once, with Codex and GJC linking to the Claude origin.
- GJC user-skill discovery requires `skills.enabled=true` and `skills.enablePiUser=true`.

## Default Direction

Use this direction unless Kyle explicitly asks otherwise:

1. Global instruction file:
   - source: `~/.claude/CLAUDE.md`
   - consumer links: `~/.codex/AGENTS.md`, `~/.gjc/agent/AGENTS.md`
2. Agent role files:
   - Claude preferred path: `~/.claude/agents/<role>.md`
   - Codex preferred path: `~/.codex/agents/<role>.md`
   - fallback: if one side is missing, use the opposite side for the same role filename
3. Codex model routing:
   - preferred path: `~/.codex/agents/ROUTING.md`
   - keep model selection separate from shared global instructions
4. Shared skills:
   - source: `~/.claude/skills/<skill-name>`
   - consumer links: `~/.codex/skills/<skill-name>`, `~/.gjc/skills/<skill-name>`

## Case Sensitivity Note

- On the usual macOS default filesystem, `AGENTS.md` and `agents.md` can point to the same single directory entry.
- Treat `~/.codex/AGENTS.md` as the canonical spelling.
- Do not assume `~/.codex/AGENTS.md` and `~/.codex/agents.md` are two separately removable files.

## Verification Checklist

- `readlink ~/.codex/AGENTS.md`
- `readlink ~/.gjc/agent/AGENTS.md`
- `ls -ld ~/.claude/agents ~/.codex/agents`
- `readlink ~/.codex/skills/<skill-name>`
- `readlink ~/.gjc/skills/<skill-name>`
