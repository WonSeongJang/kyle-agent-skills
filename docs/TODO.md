# 작업 재개 기록

## Why

[kyle]과 새 작업자가 세션이 바뀌어도 미완성 스킬 변경의 브랜치, 목적, 검증 방법을 바로 복구하게 한다.

## 현재 작업

| 브랜치 | 상태 | 목적 | 핵심 경로 |
|---|---|---|---|
| `agent/routing-exploration` | 로컬 검증 통과·PR 전 검수 | 안전한 카드의 최대 10%에서 모델 조합을 실제 탐색하고 결과를 원장에 남긴다 | `skills/orca-conductor/scripts/routing_exploration.py` |

이 표는 재개 체크포인트다. 해당 브랜치 커밋이 `main`에 포함돼 있으면 작업 완료로 해석하고, 포함되지 않았으면 아래 순서로 재개한다.

## 새 세션 재개 순서

저장소 또는 그 worktree 안에서 실행한다. 아래 첫 단계는 이 TODO의 브랜치 이름을 미리 몰라도 된다. Git 출력의 `agent/*` 후보별 `docs/TODO.md` 목적을 읽어 현재 작업을 고른다.

```bash
git worktree list --porcelain
cd <위 목록의 agent 브랜치 후보 중 이 TODO가 있는 경로>
git rev-parse --show-toplevel
git branch --show-current
bash scripts/validate.sh
```

현재 폴더가 `agent/routing-exploration`이 아니면 `git worktree list`에서 해당 브랜치의 경로를 찾아 그 폴더를 작업공간으로 사용한다. 경로를 추측하거나 라이브 `main`에서 이어서 수정하지 않는다.

## 성공 기준

- 탐색 비율 기본값은 `0`이며 기존 실제 선택을 바꾸지 않는다.
- 명시적으로 켜도 `0..10`만 허용한다.
- 명시적으로 켤 때 `--risk-assessment-complete`가 없으면 실제 선택을 바꾸지 않는다.
- 위험 표식이 있거나 안전 범위 밖 작업이면 실제 선택을 바꾸지 않는다.
- 선택 후보는 기존 점수에서 15점 이내이고 `last_resort`가 아닌 조합만 허용한다.
- stdout과 자동 원장에 실제 탐색 결과가 함께 남는다.
- `bash scripts/validate.sh`가 종료 코드 0이다.

## 작업자 경로 계약

- 모든 파일 범위는 저장소 루트 기준 상대경로로 준다.
- 예: `skills/orca-conductor/scripts/select-routing-pair.sh`
- 실행 전에 작업자가 `git rev-parse --show-toplevel`과 `git branch --show-current`로 자기 위치를 확인한다.
- worktree 절대경로는 문서에 고정하지 않고 `git worktree list` 결과를 사용한다.
