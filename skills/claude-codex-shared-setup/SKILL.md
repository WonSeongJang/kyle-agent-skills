---
name: claude-codex-shared-setup
description: Bootstrap or normalize Kyle's shared Claude/Codex/GJC machine setup using two explicit modes. Use this skill when the user wants either (1) a new-computer setup that applies the standard shared structure from scratch, or (2) an existing-computer cleanup-and-apply flow that first inspects older instruction files and prior local setup before normalizing them. Trigger on requests like "새 컴퓨터용으로 이 스킬 활용해서 적용해줘", "기존 사용 컴퓨터 정리 및 적용으로 이 스킬 활용해서 적용해줘", "초기세팅", "기존 환경 정리", "전역 지침 공유", or "이 스킬 설치하고 같이 보게 해줘". For existing machines, inspect older `agent.md`-style files first and ask before merging their content into Claude. Always add Kyle's delete-safety rules, and only symlink skills that Kyle explicitly asked to newly install or newly create.
---

# Claude Codex GJC Shared Setup

## 사람용 요약

이 스킬은 Kyle의 Claude/Codex/GJC 환경에서 전역 지침과 명시적으로 공유한 스킬은 Claude 원본 한 곳을 함께 보고, agent 역할 프롬프트는 도구별로 분리할 수 있게 정리하는 초기세팅 스킬이다.

핵심 기능은 5가지다:

1. 전역 지침 정리
   - `~/.claude/CLAUDE.md` 를 원본으로 두고, Codex와 GJC 쪽은 그 파일을 보게 맞춘다.
   - 기존 `agent.md` 계열 파일에 다른 내용이 있으면, 바로 덮지 않고 먼저 차이를 보여주고 병합 여부를 묻는다.
2. agent 역할 프롬프트 분리
   - `~/.claude/agents/` 와 `~/.codex/agents/` 는 도구별 로컬 디렉토리로 유지할 수 있다.
   - Codex는 `~/.codex/agents/` 를 우선, Claude는 `~/.claude/agents/` 를 우선 사용한다.
   - 한쪽 역할 파일이 없으면 반대쪽 경로를 fallback으로 확인한다.
   - Codex 모델 라우팅은 `~/.codex/agents/` 쪽 별도 문서/설정으로 관리한다.
3. 스킬 공유 운영 규칙 추가
   - 앞으로 Kyle이 **새로 설치하거나 새로 생성하라고 직접 요청한 스킬만** Claude 원본 + Codex·GJC 링크 방식으로 운영한다.
   - 기존 내장 스킬이나 예전부터 있던 스킬을 자동으로 전부 동기화하지 않는다.
4. 삭제 안전 지침 추가
   - 삭제는 바로 하지 않고 먼저 `~/.trash-staging/` 으로 옮긴다.
   - Kyle이 확인 후 승인했을 때만 실제 삭제한다.
5. API 시크릿 / 프록시 원칙 기본 장착
   - 외부 API 비밀 키는 공개용 env에 두지 않는다는 짧은 원칙을 전역 지침에 같이 넣는다.
   - 초기 PoC의 로컬 direct 예외는 허용할 수 있지만, 운영 전환 단계부터는 개발/운영 모두 프록시로 통일한다는 기준도 기본 장착한다.

실행 모드는 2가지다:

- `새 컴퓨터용`
  - 거의 빈 환경이라고 보고 표준 구조를 빠르게 적용한다.
  - 예상 밖의 기존 파일이 있을 때만 질문한다.
- `기존 사용 컴퓨터 정리 및 적용`
  - 현재 파일과 링크 상태를 먼저 조사한다.
  - 예전 지침이 있으면 차이를 정리해서 보여주고, 병합 여부를 물은 뒤 적용한다.

사람이 그대로 말하면 되는 문장:

- `새 컴퓨터용으로 이 스킬 활용해서 적용해줘.`
- `기존 사용 컴퓨터 정리 및 적용으로 이 스킬 활용해서 적용해줘.`




This skill has only two user-facing entry modes. Keep the execution path tied to one of these phrases so the agent does not improvise an in-between workflow.

Standardize the machine so the shared global instruction origin lives in `~/.claude`, while `~/.codex` and `~/.gjc` point to that origin through compatibility symlinks. Keep explicitly shared skills on the Claude side, but allow agent role packs and model routing to remain tool-local when needed.

## Entry Modes

### 1) 새 컴퓨터용

Use this when the machine is fresh, mostly empty, or the user wants a clean standard setup applied directly.

Recommended trigger:

- "새 컴퓨터용으로 이 스킬 활용해서 적용해줘."

Expected behavior:

- Create the standard shared structure.
- Add the required global instruction blocks.
- Point the Codex and GJC compatibility instruction files to Claude.
- Apply shared-skill linking to both Codex and GJC only for newly requested skills.
- Ask only if an unexpected pre-existing instruction file or conflicting real file is discovered.

### 2) 기존 사용 컴퓨터 정리 및 적용

Use this when the machine already has history, old dotfiles, older agent files, or a mixed Claude/Codex setup that may need cleanup first.

Recommended trigger:

- "기존 사용 컴퓨터 정리 및 적용으로 이 스킬 활용해서 적용해줘."

Expected behavior:

- Inspect current files and links first.
- Identify which files are real sources and which are just compatibility pointers.
- Summarize meaningful old instructions that may need merging.
- Ask Kyle before merging nontrivial older instruction content into `~/.claude/CLAUDE.md`.
- Normalize the final structure only after that review step.

## Mode Decision

- If the user explicitly says `새 컴퓨터용`, run the new-computer flow.
- If the user explicitly says `기존 사용 컴퓨터 정리 및 적용`, run the existing-computer flow.
- If the user only says something vague like `초기세팅`, choose the safer existing-computer flow unless the machine is clearly fresh.

## Quick Start

1. Read `references/target-layout.md`.
2. Inspect the current state before changing anything:

```bash
ls -ld ~/.claude ~/.codex ~/.gjc ~/.claude/CLAUDE.md ~/.claude/agent.md ~/.codex/AGENTS.md ~/.codex/agent.md ~/.gjc/agent/AGENTS.md ~/.claude/agents ~/.codex/agents ~/.claude/skills ~/.codex/skills ~/.gjc/skills 2>/dev/null
```

3. Pick one mode before editing anything:
   - `새 컴퓨터용`
   - `기존 사용 컴퓨터 정리 및 적용`
4. If existing files or skill directories conflict with the target structure, back them up before replacing or re-linking them.
5. Some setups already use a global instruction file, but the filename is not always the same. Check common candidates such as `agent.md`, `AGENTS.md`, and `agents.md` under `~/.claude` or `~/.codex`.
6. For the existing-computer mode, if any of those real files contain meaningful instructions that are not already in `~/.claude/CLAUDE.md`, summarize the difference and ask Kyle whether that content should be merged into Claude before replacing it with a symlink.
7. Merge the policy block from `references/global-instructions-snippet.md` into `~/.claude/CLAUDE.md` without duplicating equivalent text.
8. Include the delete-safety block from the same reference so the machine inherits Kyle's trash-staging workflow by default.
9. Include the API secret / proxy block from the same reference so new setups inherit the public-env-vs-server-env rule by default.
10. Point `~/.codex/AGENTS.md` and `~/.gjc/agent/AGENTS.md` at `~/.claude/CLAUDE.md`.
11. On case-insensitive filesystems such as the usual macOS default, `~/.codex/AGENTS.md` and `~/.codex/agents.md` may be the same filesystem entry with different spelling. Treat them as one alias, not two separate files to clean up.
12. Treat agent role files separately from shared skills. Keep `~/.claude/agents/` and `~/.codex/agents/` as tool-local directories by default; do not symlink one to the other unless Kyle explicitly asks to share them.
13. When documenting or normalizing agent role files, use the same role filenames on both sides when practical, so fallback behavior stays predictable.
14. Keep Codex model routing separate from the shared global instruction file, preferably in a Codex-local document such as `~/.codex/agents/ROUTING.md` or an equivalent tool-local file.
15. Only for skills Kyle explicitly asked to newly install or newly create in this setup, keep the origin at `~/.claude/skills/<skill-name>` and point both `~/.codex/skills/<skill-name>` and `~/.gjc/skills/<skill-name>` to it.
16. Enable GJC user-skill discovery with `gjc config set skills.enabled true` and `gjc config set skills.enablePiUser true`.
17. Do not bulk-sync preinstalled, bundled, or merely pre-existing skills unless Kyle explicitly asks to convert them too.
18. Verify all Claude→Codex/GJC links with `readlink`, then verify discovery in a fresh GJC session.

## Workflow

### 1) Confirm the mode first

- `새 컴퓨터용` means: assume a clean setup target and minimize questions.
- `기존 사용 컴퓨터 정리 및 적용` means: inspect first, explain findings, then normalize.
- Do not blend the two modes into one vague flow.

### 2) Confirm the canonical side

- Treat `~/.claude/CLAUDE.md` as the canonical global instruction file.
- Treat `~/.claude/skills/<skill-name>` as the canonical home for any shared skill.
- Treat `.codex` and `.gjc` as consumer sides. Use `~/.codex/AGENTS.md` and `~/.gjc/agent/AGENTS.md` as their compatibility instruction links.
- Treat `~/.claude/agents/` and `~/.codex/agents/` as tool-local role packs by default. Do not force them into a shared symlink topology unless Kyle explicitly asks.
- Keep Codex model routing on the Codex side so model changes do not force Claude agent files to drift.

### 3) Prepare the filesystem safely

- Ensure `~/.claude`, `~/.codex`, `~/.gjc/agent`, `~/.claude/agents`, `~/.codex/agents`, `~/.claude/skills`, `~/.codex/skills`, and `~/.gjc/skills` exist.
- If a target path already exists and is not the desired symlink, preserve it before replacing it.
- Prefer timestamped backups so the old state can be restored easily.
- Do not silently delete a real skill directory just to make a symlink.

Example:

```bash
mkdir -p ~/.claude ~/.codex ~/.gjc/agent ~/.claude/agents ~/.codex/agents ~/.claude/skills ~/.codex/skills ~/.gjc/skills
backup_dir="$HOME/.claude/backups/shared-setup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
```

### 4) Configure shared global instructions

- Create or update `~/.claude/CLAUDE.md`.
- Different tools and past setups may have used different instruction filenames. Check likely candidates such as `~/.claude/agent.md`, `~/.claude/AGENTS.md`, `~/.claude/agents.md`, `~/.codex/agent.md`, `~/.codex/AGENTS.md`, and `~/.codex/agents.md`.
- If any of those paths already exists as a real file with nontrivial content, compare it against `~/.claude/CLAUDE.md`.
- In `기존 사용 컴퓨터 정리 및 적용` mode, if that older file appears to contain instructions missing from Claude, do not silently discard it. Summarize the missing points and ask Kyle whether to merge them into `~/.claude/CLAUDE.md`.
- In `새 컴퓨터용` mode, only ask if supposedly old instruction content is unexpectedly present.
- Merge or refresh the rules blocks from `references/global-instructions-snippet.md`.
- Edit in place if a near-equivalent policy already exists; do not paste a second copy of the same rule.
- Ensure the merged content includes the delete-safety protocol, not only the skill-linking policy.
- Point the Codex and GJC compatibility instruction paths to the Claude file.
- On case-insensitive filesystems, do not try to delete `agents.md` separately from `AGENTS.md`. They may resolve to the same inode.

Useful commands:

```bash
mkdir -p "$HOME/.codex" "$HOME/.gjc/agent"
ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/.gjc/agent/AGENTS.md"
```

### 5) Configure tool-local agent directories

- Ensure both `~/.claude/agents/` and `~/.codex/agents/` exist.
- Do not symlink one agent directory to the other by default.
- Keep filenames aligned across tools when practical, such as `explorer.md`, `planner.md`, `worker.md`, so fallback behavior remains simple.
- Codex should prefer `~/.codex/agents/<role>.md`; Claude should prefer `~/.claude/agents/<role>.md`.
- If one side is missing a role file, use the opposite side as a fallback rather than silently inventing a new role.
- Keep Codex model routing in a Codex-local file instead of baking model names into the shared global instruction file.

Useful commands:

```bash
mkdir -p "$HOME/.claude/agents" "$HOME/.codex/agents"
ls -ld "$HOME/.claude/agents" "$HOME/.codex/agents"
```

### 6) Configure shared skills for newly requested installs or creates

- Apply this section only to skills Kyle explicitly asked to newly install or newly create during the current setup task.
- Do not sweep through built-in skills or older local skills and convert them automatically just because they already exist.
- When installing or creating a shared skill, make the real directory in `~/.claude/skills/<skill-name>`.
- Make `~/.codex/skills/<skill-name>` and `~/.gjc/skills/<skill-name>` symlinks to that Claude directory.
- Enable GJC user-skill discovery once with `gjc config set skills.enabled true` and `gjc config set skills.enablePiUser true`.
- If the skill already exists only in Codex as a real directory, preserve it, move or copy the canonical content into Claude, then replace the Codex path with a symlink.
- If both sides already exist with different contents, compare before deciding which one becomes canonical. Default to Claude only after preserving both states.
- Keep the folder name identical on both sides so the link remains obvious and predictable.

Useful commands:

```bash
mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gjc/skills"
ln -s "$HOME/.claude/skills/<skill-name>" "$HOME/.codex/skills/<skill-name>"
ln -s "$HOME/.claude/skills/<skill-name>" "$HOME/.gjc/skills/<skill-name>"
```

### 7) Verify and report

- Confirm that `readlink ~/.codex/AGENTS.md` and `readlink ~/.gjc/agent/AGENTS.md` both resolve to `~/.claude/CLAUDE.md`.
- If `~/.codex/agents.md` also resolves, explain whether it is just the same case-insensitive alias or a truly separate entry on that machine.
- Confirm that `~/.claude/agents/` and `~/.codex/agents/` exist and explain whether they are standalone directories or intentionally linked.
- Confirm that each explicitly shared skill under `.codex/skills/` and `.gjc/skills/` resolves to the matching Claude path.
- Report:
  - which mode was used
  - canonical global file
  - how agent role files are split between Claude and Codex
  - which skills are shared to Codex and GJC through symlinks
  - what was backed up before changes
  - any paths intentionally left as standalone copies

## Quality Gates

- Keep exactly one editable source for each shared instruction file or explicitly shared skill.
- Never discard an existing file or skill without preserving it first.
- Ask Kyle before merging nontrivial content from an older `agent.md`-style file into `~/.claude/CLAUDE.md`.
- Do not leave duplicate policy blocks in `CLAUDE.md`.
- Do not auto-convert built-in or unrelated existing skills into shared symlinked skills.
- Do not automatically force `~/.claude/agents/` and `~/.codex/agents/` into one shared directory.
- Keep Codex and GJC symlink targets explicit and easy to verify.
- If the current machine state is ambiguous, stop and explain the ambiguity instead of guessing.

## References

- `references/target-layout.md`
- `references/global-instructions-snippet.md`
