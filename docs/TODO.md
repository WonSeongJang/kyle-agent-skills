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

## 2026-08-04 — "임명장이 스킬 표준 절차를 덮는" 재발 방지 (kyle 지시, 슈퍼감독 기록)

배경: upstream-sync-1 판 개설 때 임명장의 좁은 "첫 행동 4단계" 목록이 mechanics.md의 "중계기 편성은 예외 없이 항상" 표준을 덮어 relay 미편성 → 발령 누락 정체 2회를 kyle이 육안 발견. 방향: 규칙 문장 누적이 아니라 절차의 코드·장부 이동.

- [ ] companion 개설 완결성 대조 1건 추가: 개시 선언(status) 배달 시 해당 board의 relay roster active 행이 없으면 `MISSING_RELAY` 진단을 감독에게 1회 깨움 (present/absent 결정적 대조 — 추측 판정 아님. 기존 upper report 누락 감지 패턴의 일반화).
- [ ] companion kicker 장부 대조 NUDGE (기존 항목과 통합 검토): ready 카드 present + active dispatch absent + coordinator idle → 감독 깨움. 오늘 정체 2회의 직접 방어막.
- [ ] `board-bootstrap.sh` 신설: 판 개설 기계 단계 일괄 실행 — Run 생성 → 감독 스폰+roster 대조 → companion 기동 → 중계기 스폰+roster 대조+kicker → 결과 JSON 리포트. 임명장에는 임무·헌법·금지선만 남긴다. 완성 전까지는 임명장 고정 6단계(super-conductor incident-log 2026-08-04 박제)가 임시 방어막.

## 2026-08-05 — 라우터 자기개선 고리 (kyle 설계 의도: "알아서 돌면서 좋은 모델을 찾는다", 슈퍼감독 정리)

배경: improvement-1 판에서 라우팅 2중 사고 — (1) 인계서의 "GPT 신규 작업은 luna max" 한 줄이 라우터 전체를 덮어 작업자·검수자 luna 100% 단일화 (kyle 발견), (2) 슈퍼감독도 산문 문서(roster.md)로 판정해 라우터 JSON 원본과 어긋난 정정 지시를 보냄. 관측층(routing-events JSONL 자동 기록)은 이미 설계돼 있으나 "수집→점수 반영→지분 조절" 고리가 수동.

우선순위 1 — 고리 닫기:

- [ ] 집계기 스크립트: 각 레포 `.orca/routing-events/*.jsonl`을 읽어 (모델, effort, role, taskClass)별 성적표 산출 → `routing-providers.json`의 quality 수정안을 diff/PR로 제안. kyle은 승인만 한다 (수기 점수 커밋 대체).
- [ ] 성적 지표 고정: 1차 검수 통과율, 종결까지 라운드 수, 결함 유출률(교차·마감 검수에서 뒤늦게 발견 — luna-luna 셀프 검수 사례가 근거), 비용·소요시간. "점수/비용" 축 필수 (luna 재편입 근거가 가격 인하였음).

우선순위 2 — 배분 자동화:

- [ ] 적응형 지분: 고정 experimentSharePercent(10/20%) 대신 성적 기반 자동 증감(톰슨 샘플링류). 바닥 5%·천장 40% 가드. 졸업·강등 기준 명문화: "20라운드 이상 + 신뢰구간 하한이 현직자 초과 → 정식 승격" / 반대면 강등.
- [ ] 최신성 반감기(예: 30일): 제공사의 조용한 모델 갱신에 대응해 옛 성적을 자연 소멸.

우선순위 3 — 구조적 재발 방지 (2026-08-05 사고 직결):

- [ ] 라우터 경유 강제: 임명장·인계서에 모델명 직접 기입 금지, "선택은 select-routing-pair.sh 경유"만. kyle의 모델 지정은 만료일 있는 핀(pin)으로 원장 기록 — 판 종료 시 자동 소멸 (이번 판 luna max 핀이 첫 사례).
- [ ] 동일 모델 셀프 검수 금지: reviewerFamilyAllowlist(가족 제한)에 더해 "reviewer.model != developer.model" 하드 규칙 추가.
- [ ] 문서 단일 원본화: routing-providers.json이 유일 원본, roster.md의 모델 표는 JSON에서 자동 생성 (산문-JSON 괴리로 슈퍼감독 오판정한 실사고 근거).

## 2026-08-05 — 슈퍼감독 지시 편지가 companion ack에 삼켜지는 사각지대 (실사고, 슈퍼감독 기록)

- 사고: 슈퍼감독이 gate 해소 지시를 프로젝트 Run에 type=status로 공식 전달했으나, companion이 "upperReport 없는 일반 status는 깨우지 않고 ack" 규칙대로 조용히 소비 → 감독의 미읽음 조회에 안 떠서 "공식 편지 대기" 정체 발생 (router-improvement-1, msg_8de55f6d81ab). kyle이 화면으로 발견.
- 임시 운영 규칙 (즉시 적용): 슈퍼감독→감독 지시는 편지 발송 + msg id를 명시한 터미널 깨우기를 항상 한 쌍으로.
- [ ] companion 수정 후보: 발신자가 슈퍼감독 명패이거나 payload에 superDirective=true가 있는 status는 ack 전에 감독을 1회 깨운다 (기존 구조화 상위 보고 wake와 같은 1회 보장 패턴).

- [ ] 중계기 v3 후보 — "제자리 뜀박질(busy-wait)" 감지 (2026-08-05 실사고의 나머지 반쪽, kyle 질문에서 도출): 순찰마다 판 상태 지문(카드 수·active dispatch 수·마지막 카드 created_at)을 기록·비교. 감독이 화면상 활동 중인데 판 지문이 N회(예: 3회) 연속 불변 + blocked/대기 카드가 존재하면, 감독에게 "무엇을 대기 중인지" 직문 → 답변의 대기 대상을 장부에서 결정적 대조(예: "슈퍼 편지 대기" → 해당 발신자의 read 포함 편지 존재 여부). 화면 활동만으로는 논리적 교착(읽힌 편지 대기 등)을 못 잡는다는 실측 근거.

- [ ] companion NUDGE 추가 후보 — "고아 관문" 감지 (2026-08-05 실사고: gate_404bcf8d5e01): decision_gates에 pending 관문이 있는데 슈퍼 Run에 대응 decision_gate 편지가 없으면 감독을 1회 깨워 편지 발송을 지시한다 (존재/부재 결정적 대조 — busy-wait 감지보다 단순·무오탐. 실사고: E 관문이 장부에만 생성되고 편지 미발송 → 슈퍼감독 인지까지 판 전체 대기, kyle 육안 발견).

- [ ] **원장 기록이 흔적 없이 사라지는 경로 — `--experiment-key` 형식 오류가 조용한 스킵을 만든다** (2026-08-09 판 mailbox-relay-1 실증):
  `select-routing-pair.sh` 는 `--experiment-key` 를 `[판:<board>]:<카드>` 정규식으로만 파싱한다(350행). 한국어 `판:` 접두사가 없으면 `BOARD` 가 빈 값이 되고, 그 상태로 `routing-ledger-append.sh` → `routing_ledger.py` 를 부르면 argparse 가 실패한다. 헬퍼는 `|| true` + `exit 0`(주석 19행 "본 작업 흐름은 절대 막지 않는다")이고 호출부가 `2>/dev/null` 로 stderr 를 삼키므로, **본 원장에도 격리 사이드카에도 아무것도 남지 않고 경고도 없다.**
  **왜 경고가 없나**: 실패 닫힘 설계가 "격리로 남긴다"인데, board 가 비면 격리 레코드를 만들 키 자체가 없어 격리 경로에도 못 들어간다. 즉 **격리보다 나쁘다 — 격리는 최소한 어딘가 남지만 이건 흔적이 0이다.**
  **실증 (같은 선택기, 조건만 변경)**: `board 없음+runId 없음` → 본원장 0 / 격리 0 / 진단 없음. `board 있음+runId 없음` → 본원장 0 / 격리 +1(정상 실패 닫힘). `board 있음+runId 있음` → 본원장 +1(정상).
  **이 판에서 사라진 건수**: 편성 선택 이벤트(`routing_selected_auto`) **전부**. 카드 B0·B1·B2·B3·B4·B5·B6·F-B3 등 발령 전 선택을 최소 9회 이상 돌렸으나 원장 기록 0건, 격리 0건이다. (발령 이벤트 `dispatch_auto` 는 11건이 격리로는 남았다 — 이쪽은 board 가 있었기 때문이다.)
  **고칠 방향**: board 파싱 실패 자체를 격리 사이드카에 남기거나, 형식이 안 맞으면 stderr 가 아니라 종료 코드로 호출자에게 알린다. 최소한 "조용히 사라지는 경우"를 0으로 만든다.
  관련: `roundId` 는 `^task_[0-9a-f]{8,}$` 형식만 허용한다(자유 문자열 불가). 이건 스키마가 격리로 잡아 주므로 조용한 실패가 아니다.
  **심각도 상향 (2026-08-09, 두 판 대조로 확인)**: 이건 "형식이 틀리면 기록이 사라진다"보다 나쁘다. **같은 오류를 가진 둘 중 하나는 전멸하고 하나는 무사한데, 그 차이가 어디에도 드러나지 않는다.**
  - 판 `mailbox-relay-1` 과 판 `conductor-core-contract-1` 이 **똑같이** `판:` 접두사를 빠뜨렸다.
  - 결과는 정반대였다. mailbox-relay-1 은 편성 선택 이벤트가 **통째로 소실**(본원장 0·격리 0), conductor-core-contract-1 은 **11회 호출에 11줄 다 기록·격리 0건**.
  - **차이는 실력이 아니라 우연이다.** 후자가 `ROUTING_BOARD` 환경변수를 늘 넘겨서 board 가 그쪽 경로로 받쳐졌을 뿐이다. 그 판 감독도 스스로 "운"이라고 적었다.
  - **그래서 무사한 쪽은 자기가 틀렸다는 것을 영원히 모른다.** 감사하지 않았으면 계속 몰랐을 것이고, 나중에 조건이 조금 바뀌는 순간부터 소리 없이 잃기 시작한다. 항상 실패하는 결함은 금방 발견되지만 조건부로 조용한 결함은 숨는다.
  **이건 사용자 잘못이 아니다.** 서로 다른 감독 둘이 독립적으로 같은 자리에서 틀렸다면 그건 사람 문제가 아니라 인터페이스 문제다.
  **원칙**: 우연히 동작하는 것과 올바르게 동작하는 것이 구분되지 않는 인터페이스는 그 자체가 결함이다. 형식이 틀렸는데 아무 말이 없고 결과만 조건에 따라 갈리면, 사용자는 성공을 보고 자기가 맞다고 배운다 — **틀린 것을 강화한다.**
  **따라서 필요한 것은 사용법 문서를 더 잘 쓰는 것이 아니라, 틀린 형식을 받았을 때 거부하거나 최소한 알리는 것이다.**

- [ ] **라우팅 설정에 "왜 껐는지"를 담을 자리가 없다** (2026-08-09, 판 mailbox-relay-1):
  `routing-providers.json` 은 모델을 `"enabled": false` 로 끌 수 있지만 **그 옆에 사유를 적는 필드가 없다.** 모델을 끄고 켜는 것은 정책 결정인데 근거가 파일에 안 남는다.
  **실제 사례**: `gpt-5.6-luna` reviewer max(통합 판본 236행)가 `enabled: false` 다. 이 때문에 `test_luna_max_reviewer_is_a_real_fallback_candidate` 가 `RoutingError`(`select_routing_pair.py:1013`)로 실패한다.
  끈 커밋은 `8878808 fix(orca-conductor): align routing selection policy`(2026-08-07)인데 **커밋 본문이 비어 있다.** 제목 외에 이유가 어디에도 없다. 그 커밋은 `enabled` 를 여러 건 함께 바꿨다(하나는 true, 여럿은 false).
  **그래서 지금 아무도 이 값을 다시 켤지 말지 판단할 수 없다.** 규칙이 바뀐 것은 남았는데 왜 바뀌었는지가 안 남았다 — 이것도 **침묵하는 미적용** 부류다.
  **결정(슈퍼 2026-08-09)**: 정책을 켜지 않는다. **시험을 정책에 맞춘다.** 시험을 통과시키려고 세상을 바꾸지 않는다. 의도적으로 끈 것을 이유도 모르고 되켜는 것은 위험하다.
  **고칠 방향**: `enabled` 옆에 사유 필드(예: `disabledReason`, `changedBy`, `changedAt`)를 둔다. 원장에서 "라우터 결과와 다른 선택을 하면 사유를 남겨라"를 요구하면서 정작 라우터 설정 변경에는 사유가 없다.
  **남은 작업**: `test_luna_max_reviewer_is_a_real_fallback_candidate` 의 기대치를 현재 정책(비활성)에 맞게 고치고, 주석에 "커밋 8878808 이 껐으며 본문에 이유 없음"을 인용한다. (담당 카드 미지정 — 새 카드는 만들지 않았다.)

- [ ] **관제 화면에 "소비자별 도달" 표시 붙이기 — B2 커서 계약이 자리잡은 뒤** (2026-08-10, 1d527a5 이어받음):
  `messages.read` 는 편지당 불리언 하나라 소비자(감독·중계기·companion·슈퍼)별이 아니다.
  그래서 board-status.py(1d527a5)와 board-dashboard.py 둘 다 "안 읽음 N" 숫자를 빼고
  최근 편지 사실만 보여주는 상태다. mailbox-relay-1 판의 B2 카드(소비자별 커서 통일)가
  완료되어 커서 테이블이 생기면, 그 계약을 읽어 "감독에게 아직 도달 안 한 편지"를
  두 도구에 같은 기준으로 붙인다. (2026-08-10 실측: 커서 테이블 아직 없음, R-B2 검수 failed)
