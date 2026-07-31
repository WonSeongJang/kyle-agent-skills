# 스킬 개발 작업공간 찾기

## Why

새 세션과 작업자가 설치된 라이브 스킬과 개발 중 worktree를 섞지 않고, 현재 작업을 스스로 다시 찾게 한다.

## 중요한 구분

- 설치된 `orca-conductor` 경로는 `main` 원본을 가리키는 심볼릭 링크일 수 있다.
- 기능 worktree는 자동으로 라이브 스킬이 되지 않는다. PR 병합 전까지 이 분리가 안전장치다.
- 미완성 작업의 위치는 절대경로 메모가 아니라 Git의 `worktree` 목록이 알려준다.

## 새 세션에서 찾는 순서

현재 스킬 경로 또는 저장소 안에서 아래를 실행한다. `docs/TODO.md`의 브랜치를 미리 아는 것은 전제하지 않는다. Git 출력의 `agent/*` 브랜치들을 후보로 삼고, 각 후보 worktree의 TODO 목적을 읽어 현재 작업과 맞는 것을 고른다.

```bash
git worktree list --porcelain
cd <위 목록의 agent 브랜치 후보 중 docs/TODO.md 목적이 맞는 경로>
git rev-parse --show-toplevel
git branch --show-current
sed -n '1,240p' docs/TODO.md
```

`git worktree list --porcelain` 자체가 worktree 경로와 브랜치를 함께 보여주는 독립 원장이다. TODO는 후보를 찾은 뒤 목적과 성공 기준을 확인하는 두 번째 근거다. 현재 브랜치가 다르면 수정하지 않는다.

## 상대경로 계약

작업 카드, 작업자 프롬프트, TODO, 검수 인계에는 저장소 루트 기준 상대경로만 적는다.

```text
skills/orca-conductor/SKILL.md
skills/orca-conductor/scripts/routing_exploration.py
skills/orca-conductor/scripts/tests/test_routing_exploration.py
```

작업자는 자기 worktree 루트에서 명령을 실행한다. 절대경로는 `git worktree list`로 작업공간을 찾는 순간에만 사용하고 기록에는 고정하지 않는다.

## 완료 흐름

1. 기능 worktree에서 `bash scripts/validate.sh`를 실행한다.
2. 변경 경로만 지정해 커밋한다.
3. 브랜치를 push하고 PR 및 CI를 확인한다.
4. 병합 전에는 라이브 `main` 링크를 바꾸지 않는다.
5. 병합 뒤 살아 있는 Orca 프로젝트 감독에게 다음 카드 경계에서 스킬 재독을 통지한다.
