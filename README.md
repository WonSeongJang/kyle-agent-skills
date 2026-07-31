# kyle-agent-skills

## Why

[kyle]의 개인 에이전트 스킬을 Git으로 되돌릴 수 있게 관리하고, 수정 중인 스킬이 Claude·Codex·GJC의 라이브 환경에 바로 섞이지 않게 한다.

## 구조

```text
skills/                 Git으로 관리하는 스킬 원본
scripts/validate.sh     공통 검증 진입점
.github/workflows/      push와 PR 자동 검증
```

라이브 실행 위치는 `main` 작업 폴더의 스킬을 심볼릭 링크로 바라본다.

```text
~/.claude/skills/orca-conductor -> ~/Dev/kyle-agent-skills/skills/orca-conductor
~/.codex/skills/orca-conductor  -> ~/Dev/kyle-agent-skills/skills/orca-conductor
~/.gjc/skills/orca-conductor    -> ~/Dev/kyle-agent-skills/skills/orca-conductor
```

## 변경 흐름

라이브 `main`에서 직접 개발하지 않는다. 작업마다 별도 worktree를 만든다.

```bash
git -C /Users/fw_m1/Dev/kyle-agent-skills worktree add \
  /Users/fw_m1/Dev/.worktrees/kyle-agent-skills/<작업이름> \
  -b agent/<작업이름> main
```

worktree에서 수정과 검증을 끝낸 뒤 커밋·push·PR 검수를 거쳐 `main`에 병합한다. 라이브 링크는 `main`만 바라보므로 작업 중인 변경은 실제 세션에 적용되지 않는다.

## 검증

```bash
bash scripts/validate.sh
```

## 되돌리기

문제가 생기면 `main`에서 정상 커밋으로 되돌린다. 링크 교체 전 폴더와 링크는 각 실행 위치의 `.staging/`에 보존한다.
