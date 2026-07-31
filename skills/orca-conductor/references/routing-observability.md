# 라우팅 실행 기록 원장

## 자동 기록 2층 구조 (2026-07-27 kyle 승인 — "규율이 아니라 장치로")

원장의 대부분은 스크립트가 자동으로 쓴다. LLM(감독)의 수기 의무는 판단이 필요한 이벤트로 좁힌다.

| 이벤트 | 기록 주체 | 방식 |
|---|---|---|
| `routing_selected_auto` (편성 선택 전체 결과) | `select-routing-pair.sh` | 실행 시 자동 append |
| `dispatch_auto` (발령 카드·터미널) | `dispatch-safe.sh` | 발령 성공 시 자동 append |
| `worker_done_auto` (완료 taskId·dispatchId) | `conductor-companion.sh` | 신호 감지 시 자동 append |
| `review_finished` (치명/중요/사소 판정) | **감독 수기** | 체크포인트 커밋 턴에 함께 기록 |
| `checkpoint_committed` / 랠리 총평 | **감독 수기** | 〃 (rally-log와 같은 턴) |

- 원장 경로: `$ROUTING_LEDGER_FILE` 환경변수 우선, 없으면 실행 위치 git root의 `.orca/routing-events/<판>.jsonl` (판 이름은 `--experiment-key '[판]:카드'`에서 자동 파싱, dispatch-safe·companion은 `$ROUTING_BOARD`).
- 자동 이벤트는 스키마의 `*_auto` 타입이며 실패해도 본 작업을 막지 않는다(조용히 스킵).
- 배경: 2026-07-27 openapi-fix 판에서 수기 의무만으로는 원장이 통째로 비는 실사고 — 기억 의무를 장치로 대체.


## Why

모델별 감각 점수를 실제 성과로 교체할 수 있도록, 라우팅 당시 조건과 이후 결과를 비교 가능한 원시 이벤트로 보존한다.

## 목차

- 저장 위치와 역할
- 연결 단위
- 이벤트 종류와 기록 시점
- 작업 분류
- 측정값 원칙
- 개인정보와 크기 제한
- 점수 계산 단계

## 저장 위치와 역할

기계 원본은 대상 레포 본체의 `<레포루트>/.orca/routing-events/<판이름>.jsonl`에 append-only JSONL로 남긴다. 워크트리는 판 종료 때 사라질 수 있으므로 저장하지 않는다. `.orca/`는 gitignore에 넣고 디스크 원장으로 보존한다.

- 한 줄은 `routing-events.schema.json`을 만족하는 JSON 객체 1개다.
- 이미 쓴 줄은 수정하지 않는다. 정정은 새 `quality_feedback` 이벤트로 남긴다.
- `rally-log.md`는 사람이 읽는 회고다. JSONL을 대신하지 않으며, JSONL은 회고 문장을 대신하지 않는다.
- 여러 프로젝트 통계는 각 레포 원장을 읽어 합산한다. 원본을 중앙 파일로 옮기거나 덮어쓰지 않는다.

## 연결 단위

- `eventId`: 이벤트 한 줄의 유일한 ID
- `runId`: 한 모델 터미널에 발령한 실행 1회의 ID
- `roundId`: 구현 실행과 그 결과를 검수한 실행을 묶는 라운드 ID
- `taskId`: Orca 카드 ID
- `board`: `[판:]` 이름
- `repoId`: Orca repo ID. 절대경로 대신 사용한다.

재발령·모델 전환·수정 라운드는 새 `runId`를 만든다. 같은 티키타카 라운드의 구현과 검수는 같은 `roundId`를 쓴다.

## 이벤트 종류와 기록 시점

### `routing_decision`

**(2026-07-27 자동화)** 발령 직전 선택 근거는 `select-routing-pair.sh`가 `routing_selected_auto` 이벤트로 자동 기록한다 — 감독이 이 이벤트를 수기로 쓰지 않는다. 아래 정밀 스키마는 자동 이벤트가 담지 못하는 값을 집계기가 파생 계산할 때의 기준이다. 선택된 모델뿐 아니라 제외·후순위 후보도 남겨 나중에 선택 근거를 재계산할 수 있게 한다.

- 작업 문맥: 역할, 작업 종류, LIGHT/HEAVY, 라운드, 위험 표식
- 선택: provider, model, modelVersion, effort, profile
- 후보별 가용성, 제외 이유, 품질 prior, 관측 품질, 쿼터·계열 분리 점수
- 라우터 버전, 탐색 선택 여부, 선택 확률
- 발령 직전 쿼터 스냅샷

`qualityPrior`와 `observedQuality`는 당시 선택기의 입력 스냅샷이지 정답 라벨이 아니다.

`routing_selected_auto.payload.shadow`는 2026-07-31부터 실제 발령을 바꾸지 않는 비교 자료다. `task_class`, 선택된 작업자·검수자의 `harness`, 기존 점수, `taskClassPrior` 합계, 그림자 점수를 기록한다. stdout의 실제 선택과 shadow 선택이 달라도 발령은 stdout을 따른다. `taskClassPrior`는 수동 가설이므로 `observedQuality`로 해석하거나 운영 성과처럼 보고하지 않는다.

### `execution_finished`

**(2026-07-27 자동화)** 정상 완료는 companion이 `worker_done_auto`로, 발령은 `dispatch_auto`로 자동 기록된다. 감독 수기는 자동 경로가 못 잡는 경우만: 명시 실패, 취소, 일꾼 사망 후 수동 종결.

- 상태: completed, failed, cancelled, not_started
- 실제 실행 시간, 수정 파일 수, 토큰 사용량과 측정 출처
- 구현자가 수행한 검증 이름·종료 코드

### `review_finished`

검수 worker_done을 프로젝트 감독이 대조한 뒤 기록한다.

- verdict: pass, revise, blocked
- 치명·중요·사소·관찰 개수
- 검수자가 직접 수행한 실물·테스트 검증과 종료 코드
- 검수자 모델과 구현 `runId`

### `checkpoint_committed`

검수 합격 단위 체크포인트 커밋 직후 기록한다. SHA가 없으면 합격 통계의 최종 성공으로 세지 않는다.

### `quality_feedback`

나중에 검수 오보, 검수 누락, 실제 사용 회귀, 배틀 승패가 확인될 때 기록한다. 과거 이벤트를 수정하지 않고 `targetRunId`를 참조한다.

## 작업 분류

`taskClass`는 아래 하나만 선택한다.

- `targeted_implementation`: 방향이 정해진 표적 구현
- `frontend`: 화면·상호작용·레이아웃
- `architecture`: 새 경계·모듈·프로토콜 설계
- `research`: 외부 또는 저장소 조사
- `security`: 인증·권한·비밀·공격면
- `concurrency`: 경합·트랜잭션·동기화
- `bugfix`: 원인과 위치가 확인된 결함 수정
- `docs_config`: 문서·문구·설정
- `qa`: 읽기 전용 검수·실물 QA
- `other`: 위 분류에 들어가지 않는 경우

복수 성격은 가장 중요한 하나를 `taskClass`로 고르고 나머지는 `riskFlags`에 넣는다. 작업 중 HEAVY 사실이 드러나면 다음 실행부터 새 분류·위험 표식을 기록하며 과거 줄은 고치지 않는다.

## 측정값 원칙

- 측정값은 값과 `source`를 함께 남긴다: `measured`, `reported`, `derived`, `unknown`.
- 모르는 값을 0으로 기록하지 않는다. `value: null`, `source: unknown`을 쓴다.
- 품질, 시간, 토큰, 쿼터, provider 독립성은 별도 필드로 보존한다. 원장에서 하나의 종합 점수로 합치지 않는다.
- 성공은 `검수 pass + checkpoint SHA`로 확정한다. worker_done만으로 성공 처리하지 않는다.
- 검수 발견 수는 작업 난이도와 검수자 성향의 영향을 받으므로 단독 품질 점수로 쓰지 않는다.
- 모델 ID와 모델 버전을 분리한다. 버전이 바뀌면 같은 통계 집단으로 자동 합치지 않는다.

## 개인정보와 크기 제한

프롬프트 전문, 코드, diff, 터미널 원문, 비밀값, 사용자 입력, 절대경로를 기록하지 않는다. 근거는 Orca task/message/commit ID와 검증 명령의 짧은 이름만 남긴다. 이벤트 한 줄은 32KB 이하로 제한하고 후보는 실제 평가한 상위 10개까지만 남긴다.

## 점수 계산 단계

1. 처음에는 `routing-providers.json`의 `quality`를 `qualityPrior` 의미로만 사용한다.
2. `harness × 모델 × 역할 × taskClass × effort × modelVersion`별 표본을 만든다.
3. 표본 수, 첫 검수 합격률, 치명·중요 발생률, 평균 라운드 수, 체크포인트 성공률을 따로 계산한다.
4. 최근 30일 60%, 31~90일 30%, 이전 10%처럼 최근 결과를 더 크게 반영한다.
5. 표본이 적으면 prior 쪽으로 수축하고 `sampleCount`와 신뢰 구간을 함께 표시한다.
6. 배틀·유사 작업의 직접 비교가 충분해지면 Bradley-Terry 상대 승률을 추가한다.
7. 선택 확률과 결과가 충분히 쌓인 뒤에만 contextual bandit을 시험한다. 그 전에는 자동 학습으로 운영 선택을 바꾸지 않는다.

파생 점수와 집계 파일은 언제든 다시 만들 수 있는 캐시다. JSONL 원장만 원본이다.
