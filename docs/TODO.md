# 작업 재개 기록

## Why

[kyle]의 Orca 판에서 구형 중계기의 보고 권한이 사라져도 감지 결과가 묻히지 않고 현재 프로젝트 감독이 복구 판단을 이어받게 한다.

## 현재 작업

| 브랜치 | 상태 | 목적 | 핵심 경로 |
|---|---|---|---|
| `agent/relay-legacy-fallback` | 보완 구현·검증 중 | 중계기와 현재 dispatched 작업자의 `[LEGACY READ-ONLY]` 보고 실패를 task+dispatch별로 감지하고 현재 감독을 한 번만 깨운다 | `skills/orca-conductor/scripts/conductor-companion.sh`, `skills/orca-conductor/references/mechanics.md` |

## 새 세션 재개 순서

저장소 또는 worktree 안에서 아래 순서로 현재 작업공간을 다시 찾는다.

```bash
git worktree list --porcelain
cd <agent/luna-effort-routing 브랜치의 worktree>
git rev-parse --show-toplevel
git branch --show-current
bash scripts/validate.sh
```

현재 브랜치가 `agent/relay-legacy-fallback`이 아니면 수정하지 않는다.

## 성공 기준

- 중계기가 lifecycle 보고에서 `[LEGACY READ-ONLY]`를 받으면 같은 명령을 재시도하지 않고 구조화된 표식을 남긴다.
- companion은 구조화된 표식 또는 기존 `legacy_read_only` 오류를 감지해 현재 프로젝트 감독을 한 번만 깨운다.
- companion은 실행 기록(run)을 자동 인수하거나 카드·dispatch 상태를 직접 바꾸지 않는다.
- 같은 표식이 화면에 남아 있어도 중복 기상이 발생하지 않는다.
- 서로 다른 task+dispatch에서 같은 원문 오류가 나면 각각 한 번씩 기상한다.
- 중계기가 표식을 작업자 화면에 보내지 않아도 companion이 작업자 화면의 거부 원문을 직접 감지한다.
- launchctl처럼 PATH가 축소된 환경에서도 실제 Orca 실행 파일을 찾아 `task-list/read/send` 끝단이 동작한다.
- Claude/Fable 터미널 렌더링이 `BB`처럼 붕괴해도 dispatch transcript에서 lifecycle 거부를 복구한다.
- `bash scripts/validate.sh`가 종료 코드 0이다.

## 작업자 경로 계약

- 모든 파일 범위는 저장소 루트 기준 상대경로로 적는다.
- 실행 전에 `git rev-parse --show-toplevel`과 `git branch --show-current`로 작업공간을 확인한다.
- worktree 절대경로는 문서에 고정하지 않고 `git worktree list` 결과를 사용한다.

## 후속 운영 규칙화 TODO

### Why

프로젝트 감독이 사람에게 잘못 질문하거나, 실행 중인 감독에게 지시를 끼워 넣어 작업이 멈추는 일을 중계기가 안전하게 감지하고 복구할 수 있게 한다.

- [ ] 상위 보고 조건을 `판 전체 완료` 또는 `실제 사람 판단 필요`로 한정하고, 프로젝트 내부 결정 관문은 프로젝트 실행 기록(run) 안에서 처리하도록 계약과 검증을 정리한다.
- [ ] 프로젝트 감독이 공식 상위 보고 없이 `[kyle]` 또는 사용자에게 직접 승인·판단을 요청한 뒤 대기하는 상태를 `misrouted_human_decision`으로 감지하고, 중계기가 해당 감독만 한 번 깨우도록 한다.
- [ ] 감독에게 지시하기 전에 현재 상태를 확인하고, `working`이면 중단하거나 새 입력을 보내지 않으며 `idle`인 안전한 경계에서만 전달하도록 규칙화한다.
- [ ] 터미널 지시는 텍스트 수신만으로 완료 처리하지 않고, Enter 적용과 새 도구 실행 또는 문맥 사용량 증가까지 확인해야 실제 시작으로 인정하도록 검증한다.

## 후속 TODO: 라우팅 원장 무결성과 Orca 공식 계약

### Why

실제 작업 성과가 모델 선택에 반영되도록, 선택부터 검수·체크포인트까지 같은 실행 기록으로 연결하고 누락을 조용히 허용하지 않게 한다.

### 2026-08-03 읽기 전용 실측

- 확인한 3개 저장소의 `.orca/routing-events/*.jsonl`에는 총 150건이 있으며 JSON 문법은 모두 유효했다.
- 이벤트는 `worker_done_auto` 136건, `routing_selected_auto` 12건, `routing_decision` 1건, `dispatch_auto` 1건이다.
- `review_finished`, `checkpoint_committed`, `quality_feedback`는 모두 0건이다.
- 150건 중 139건의 `board`가 `unknown`이고, 9건은 실제 판 이름 대신 `판`으로 기록됐다.
- 149건의 `runId`와 `roundId`가 실제 연결값이 아니라 `auto`다.
- 자동 모델 선택 12건 중 3건은 선택 결과가 아니라 명령 사용법 출력이 `payload.raw`로 저장됐다.
- 현재 선택기는 원장 결과를 읽지 않는다. `routing-providers.json`의 고정 품질 점수, 현재 쿼터, 모델 계열 분리 점수만 사용한다.
- 사람이 쓰는 `references/rally-log.md`에는 모델별 수렴 기록이 있으나 자동 점수 입력으로 연결되지 않으며, 최신 항목은 2026-07-28이다.

### 해야 할 일

- [ ] `[판:<이름>]`에서 실제 판 이름을 추출하도록 board 파싱 계약과 회귀 시험을 고친다.
- [ ] 선택·발령·완료·검수·체크포인트가 실제 `taskId`, `dispatchId`, `runId`, `roundId`로 연결되게 한다. `auto`와 `unknown`은 개발용 명시 모드가 아니면 기록 실패로 관찰 가능하게 남긴다.
- [ ] 라우터 출력이 유효한 구조화 JSON일 때만 `routing_selected_auto`를 기록하고, 사용법·오류 문자열을 성과 데이터로 저장하지 않는다.
- [ ] 프로젝트 감독의 검수 종결과 체크포인트 커밋에서 `review_finished`와 `checkpoint_committed`를 자동 기록한다. 사후 회귀·오보 정정은 `quality_feedback` append-only 이벤트로 남긴다.
- [ ] 원장 이벤트의 스키마 검증, 이벤트 연결 무결성, 중복 방지, 한 줄 32KB 제한을 자동 시험한다.
- [ ] 모델별 첫 검수 합격률, 치명·중요 발견률, 평균 라운드 수, 체크포인트 성공률을 집계하는 읽기 전용 도구를 만든다.
- [ ] 표본 수와 신뢰도를 함께 보여 주고, 충분한 표본이 쌓이기 전에는 자동 학습 결과가 실제 배정을 바꾸지 못하게 한다.
- [ ] 기존 150건은 원문을 수정하지 않는다. 연결 가능한 이벤트만 파생 집계에서 사용하고, 연결 불가능한 데이터는 `unknown` 표본으로 격리한다.

### Orca 포크 계약 후보

- [ ] 선택 스크립트마다 제각각 파일에 쓰게 두는 대신, Orca 오케스트레이션 수명주기에서 공식 라우팅 이벤트를 append-only로 기록하는 방안을 설계한다.
- [ ] Orca가 `taskId+dispatchId+runId+role roster pane`을 권위 정보로 제공하고, `orca-conductor`는 모델 선택 이유와 검수 판정 같은 보충 정보만 추가하는 책임 분리를 검토한다.
- [ ] Orca DB를 권위 원장으로 정할 경우 JSONL은 내보내기·분석용 파생물로 두고, DB와 JSONL의 중복·순서·재시작 복구 계약을 명시한다.
- [ ] 위 계약은 별도 설계 카드와 독립 검수로 확정한다. 현재 Luna 라우팅 변경과 섞어 구현하지 않는다.
