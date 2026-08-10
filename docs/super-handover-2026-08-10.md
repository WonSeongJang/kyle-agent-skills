# 슈퍼감독 인수인계 — 2026-08-10

작성: 2026-08-10 22:40 KST · 전임 슈퍼감독 세션
독자: 이 자리를 이어받는 새 슈퍼감독 세션

**모든 항목은 기억이 아니라 장부·파일에서 실측했다. 근거 명령을 함께 적었다.
실측하지 못한 것은 "모름"으로 표시했고 숨기지 않았다.**

---

## 0. 먼저 알아야 할 것 — 다른 세션이 같은 저장소에서 일하고 있다

`kyle-agent-skills` 저장소에 **내가 만들지 않은 오늘 커밋이 10개** 있다. kyle이 대시보드 작업을
다른 세션에 맡겼다("대시보드 파일은 만든 세션에게 맡겨라" → 이후 웹 관제로 이관).

```bash
cd /Users/fw_m1/Dev/kyle-agent-skills && git log --since="2026-08-10 00:00" --oneline --no-merges
```

| 내 것 아님 (다른 세션 소유) | 무엇 |
|---|---|
| `b9bc83c` `4cce391` `786c753` `5080448` `fec5a85` | 우편함 가시성 개편 |
| `901166a` | **웹 관제(`board-dashboard.py`)를 기본 화면으로 기록 — 내 오전 결정을 대체** |
| `4209ea2` `a2c3778` `d9ee186` `c2aac64` | 대시보드 후속 |

- **`skills/orca-conductor/scripts/board-dashboard.py`** (60,639바이트, 18:02 수정) — 웹 관제.
  기본 `http://localhost:8787`. **kyle의 기본 관제 화면이다** (2026-08-10 kyle: "웹이 더 편하다").
  내가 만든 `board-status.py`(CLI)는 보조로 남았다.
- **`skills/orca-conductor/references/rally-log.md` 에 미커밋 변경이 있다** (`git status --short`로 확인).
  **내 것이 아니다. 커밋하거나 되돌리지 마라.**
- `.commandcode/` 도 미추적 상태로 있다. 내 것이 아니다.

**행동 규칙**: 대시보드·우편함 관련 파일은 손대지 마라. 필요하면 kyle을 통해 그 세션에 요청하라.

---

## 1. 슈퍼감독 신분과 우편함 명령

### 실측된 주소

```bash
ORCA_BUNDLE="/Users/fw_m1/Dev/orca-kyle/dist/mac-arm64/Orca Kyle.app/Contents/Resources/bin/orca-kyle"
"$ORCA_BUNDLE" orchestration run-show --id run_b58669d80d88 --json
```

| 항목 | 값 | 상태 |
|---|---|---|
| 슈퍼 Run id | `run_b58669d80d88` | **이것이 유효한 주소다** |
| coordinator_handle | `term_671919bc-5a12-4c2f-9fca-2bec648cd6a4` | **죽었다** (`terminal_handle_stale`) |
| coordinator_pane_key | `27e67c54-7b85-4d7a-862e-0efe48d5c789:0e2e3607-a158-45da-95b7-abb0b01f5062` | 살아 있다 |
| 그 pane의 현재 handle | `term_80560839-7c33-44e0-9f90-62e7730b3f95` | 살아 있다 (제목 "중계기 문제 확인", `~/Dev/Rottie`) |
| consumer_generation | 17 | — |

### **주의 — handle로 주소를 삼지 마라**

편지 수를 직접 세어 확인했다.

```bash
DB="/Users/fw_m1/Library/Application Support/Orca Kyle/orchestration.db"
sqlite3 -readonly "$DB" "select count(*) from messages where to_handle='run:run_b58669d80d88';"          # 488
sqlite3 -readonly "$DB" "select count(*) from messages where to_handle='term_671919bc-...';"             # 79  (옛 handle, 과거분)
sqlite3 -readonly "$DB" "select count(*) from messages where to_handle='term_80560839-...';"             # 0
```

**`run:run_b58669d80d88` 만 실제로 편지를 받는다.** handle은 Orca 재시작 때 바뀌는 라우팅 값이다.
전임자는 오전에 이 때문에 편지 5통을 못 받았다.

### 읽기 (ack 포함)

```bash
# 1) 비파괴 확인 — 읽음 표시 안 함. 상태 파악은 항상 이걸 먼저.
"$ORCA_BUNDLE" orchestration check --run run_b58669d80d88 --peek --json
#    실측: ok=true, 편지 100통 반환. result 키 = messages/count/acknowledged/runId

# 2) FIFO 배치 수령 — 읽음 처리되고 delivery_id 가 붙는다
"$ORCA_BUNDLE" orchestration check --run run_b58669d80d88 --json

# 3) 앞 배치 확인 응답(ack) 후 다음 배치
"$ORCA_BUNDLE" orchestration check --run run_b58669d80d88 --ack <delivery_id> --json

# 4) 새 편지가 올 때까지 대기 (foreground 금지 — 사용자 대화를 막는다)
"$ORCA_BUNDLE" orchestration check --run run_b58669d80d88 --wait --timeout-ms 900000 --json
```

`--peek` 에서는 `delivery_id` 가 `None` 이다(실측). ack 대상 id는 `--peek` 없이 받은 배치에만 붙는다.

### 보내기

```bash
"$ORCA_BUNDLE" orchestration send \
  --to run:<판 Run id> \
  --subject '<제목>' \
  --body '<본문>' --json
```

- 판A로 보낼 때 `--to run:run_01553b7a106b`, 판B는 `--to run:run_7879c26f3598`.
- 실측 성공 예: `msg_559528216d09` (INT-1 `--run` 계약 결정 통지).
- **터미널 글은 스크롤로 사라진다. 결정·근거는 반드시 편지로 남겨라.**

### 감독 터미널에 직접 말하기

```bash
orca terminal send --terminal <handle> --text '<한 줄>' --enter
```

**여러 줄을 넣지 마라.** 호스트가 줄마다 Enter로 제출해 여러 메시지로 쪼개진다(실측: 1121자 카드가
5개 작업으로 인식됨). 긴 지시는 파일로 쓰고 터미널엔 경로 한 줄만 준다.

### 지금 밀린 편지

**`--peek` 기준 100통.** 대부분 지나간 진행 보고와 하트비트다. 전부 읽으려 하지 말고
`escalation` / `decision_gate` / `question` / `worker_done` 부터 봐라.

---

## 2. 지금 유효한 임시 규칙

### (A) `ocx v2 mode v1` — **여전히 적용 중. 되돌리지 않았다**

```bash
ocx v2 status
#   multi_agent_v2: OFF
#   multi_agent_mode: v1 — ALL models forced to v1 surface (upstream pins overridden)   ← 실측
```

- **왜**: opencodex 프록시가 codex 대화에 `"The model catalog changed after Codex started; do not set
  model or reasoning_effort overrides"` 를 주입해, 감독이 `--model` 붙은 발령을 전부 거부했다.
  판A가 16번 순찰 동안 정체했다.
- **진짜 원인**: opencodex의 로케일 버그. `app-server-processes.ts:493,503` 이 `ps -o lstart` 를
  `Date.parse` 로 읽는데 한국어 로케일이면 `NaN` → state=`unknown` → `collaboration.ts:249` 가
  `unknown` 을 `stale` 과 똑같이 취급해 그 문장을 낸다.
  대조군 실측: 한국어 `Date.parse`=NaN / `LC_ALL=C` `Date.parse`=1786331599000.
- **해제 조건**: opencodex가 이 버그를 고치거나, 로케일 문제를 다른 방법으로 해소했을 때.
  **해제 명령**: `ocx v2 mode default`
- **해제 전 반드시**: 새 codex 세션에서 그 지시문이 다시 뜨는지 확인하라. 뜨면 되돌려라.
- **적용 방법의 함정**: `ocx` 는 "새 세션부터 적용"이라고 하는데 그 세션은 **codex 프로세스** 단위다.
  TUI의 `/new` 로 대화만 새로 만들면 여전히 걸린다(실측). `/quit` 후 같은 명령으로 재기동해야 한다.
- 박제: `skills/conductor/references/agent-runners.json` codex quirks (커밋 `b7ae2cc`, `4f7e9df`)

### (B) 부하 보류 — **해제됨 (2026-08-10 22:2x)**

- 걸었던 이유: 1분 부하 33.79 / 5분 25.23. 원인은 우리 판이 아니라 `ChatGPT.app`(약 2.5코어).
- kyle이 ChatGPT.app을 닫자 **33.79 → 6.74**, 메모리 여유 48% → 63%. 대조군으로 원인 확정.
- 두 판에 해제 통지 완료. 동시 활성 1장 제한도 해제, 판당 3장 복귀.
- **부수 확인**: ChatGPT.app을 닫아도 codex CLI는 opencodex 프록시로 직접 붙어 판이 안 멎는다.
  앞으로 무거우면 앱부터 닫는 선택지가 있다.

### (C) 표준으로 승격된 것 (임시 아님, 참고)

| 규칙 | 위치 |
|---|---|
| 80%는 자동 교대선이 아니다 · 자동 압축은 gpt 계열만 | `references/mechanics.md` (커밋 `b494c87`, `c3f7c7e`) |
| 임명장 필수 문구 9종 · 발부 전 항목 수를 센다 | `references/appointment-template.md` (커밋 `5c7cfe4`, `c9a5a10`) |
| 진행 가시성을 감독을 깨워서 사지 마라 | `references/mechanics.md` (커밋 `4129be8`, `c9a5a10`) |
| 중계기 교대 시 카드 발령도 옮긴다 | `references/mechanics.md` (커밋 `6dac235`) |
| 검수는 새 세션 · 시간 기준선 · 심판 층 | `references/tiki-taka.md` (커밋 `766293e`) |
| 자기 모델 검수 차단은 코드에 실재 (`select_routing_pair.py:337`) | `references/roster.md` (커밋 `f7ad717`) |

---

## 3. 내가 하겠다고 해놓고 안 끝낸 일

**전부 미완료다. 하나도 처리하지 못했다.**

1. **"죽은 작업자를 되살리는 일에 주인이 없다"를 표준에 박기** — 오늘 마지막으로 드러난 구멍.
   중계기는 정체를 신고했고(12:06·13:14·13:21), 감독은 내 보류를 지키느라 조용했고, 나는 kyle을
   기다렸다. **그 결과 죽은 카드 둘이 4시간 반 방치됐다.** 신고와 조치 사이에 주인이 없다.
   → 아직 안 씀.
2. **중계기가 "보류 중 감독 조용함"을 정체로 오판하는 문제** — 오늘 stall escalation 3건이 전부
   내 보류 때문이었다. 보류 상태를 중계기가 알 방법이 없다. → 아직 안 고침.
3. **사전검증(preflight)을 표준에 넣기** — 판A 감독이 스스로 만든 단계이고, 표준 전체를 grep해도
   `사전검증`·`preflight` 가 없다. 이번에 빨간 main 위에 틀린 체크포인트로 반대 계약 둘을 합칠 뻔한
   것을 이게 막았다. → 아직 안 넣음.
4. **헤드리스 중계기(DeepSeek) vs luna 비교 결과 보고** — 15:22부터 판B에서 나란히 돌고 있다.
   최근 판정 3줄은 정상(`정체`/`진행` 판별, 조치 1건). **비교 결론은 아직 안 냄.**
   원본: `/Users/fw_m1/Dev/kyle-agent-skills/.orca/relay-logs/mailbox-relay-1.relay-log.md` 의 `| patrol |` 줄.
5. **잠든 판 26개의 장부-실물 어긋남 훑기** — kyle에게 제안했으나 답을 못 받았고 실행 안 함.
6. **판B 실패 9장 분류 보고** — 감독에게 지시했고 진행 중. 결과 미수령.
7. **A11 제외 사유 확인** — 사전검증이 권장 병합 순서에서 A11을 뺐는데 근거를 안 적었다.
   감독에게 검증자한테 확인하라 지시(병행). **결과 미수령.**
8. **INT-1 병합 관문을 kyle에게 올리기** — 판A가 `INT-1-PREMERGE2` 합격 시 나에게 보고하기로 함.
   아직 안 옴.

---

## 4. 내가 띄운 백그라운드 프로세스

```bash
ps -axo pid,ppid,etime,command | grep -E "conductor-companion|relay-patrol\.py" | grep -v grep
```

| PID | PPID | 경과(22:40 기준) | 무엇 | 죽여도 되나 |
|---|---|---|---|---|
| `25058` | 1 | 11:43 | companion — 판A(`conductor-core-contract-1`) | **안 된다.** 죽으면 판A 감독이 편지 와도 안 깨어난다 |
| `24635` | 1 | 07:57 | companion — 판B(`mailbox-relay-1`) | **안 된다.** 같은 이유 |
| `36410` | 1 | 07:14 | `relay-patrol.py` 헤드리스 중계기 시험 — 판B | **된다.** 시험용이고 판B엔 luna 중계기가 따로 살아 있다 |
| `57081` | 1 | 09:39 | opencodex 프록시 (`bun.exe`, 포트 10100) | **안 된다.** 모든 codex 작업자가 이걸 거친다. 죽으면 502로 작업자가 죽는다 |

- companion은 **감독 자기 pane에서만** 띄워야 한다. 내 셸에서 대신 띄우면
  `consumer_owner_mismatch` 로 거부된다(실측). 재기동은 감독에게 시켜라.
- companion 실행 시 **`ORCA_BIN=<번들 절대경로>` 를 반드시 넘겨라.** 안 넘기면 PATH의 `orca` 로
  떨어지고 그건 `roster` 를 몰라 `ROSTER_FAIL_CLOSED reason=resolve_failed` 로 닫힌다(실측).

### 하네스 Monitor

| task id | 무엇 |
|---|---|
| `bt2kla2d8` | 슈퍼 우편함 새 편지 + 부하·메모리·프로세스·companion 관문 알림 (persistent) |

- 부하 판정은 **1분·5분을 둘 다** 본다. 관문 = 1분 ≥ 12 가 연속 2회. 해제 = 1분 ≤ 9 **그리고** 5분 ≤ 11.
  (1분만 보고 해제했다가 5분이 15인데 풀린 사고가 있어 고쳤다.)
- companion 은 **PPID=1 인 상주 것만** 센다. 회귀 시험이 띄우는 `board_test` companion을 세지 않기 위해서다.
- 알림에 CPU 상위 3개가 붙어 온다. 원인을 매번 다시 찾지 않아도 된다.
- **세션이 끝나면 이 Monitor도 끝난다.** 새 세션은 자기 것을 새로 걸어야 한다.
  명령 원문은 이 문서 끝 부록에 없다 — **모름**. 필요하면 `TaskStop` 결과에 원문이 찍히므로
  기존 것을 멈추기 전에 그 출력을 보관하라.

---

## 5. 살아 있는 판 — 현재 국면과 열린 결정

```bash
"$ORCA_BUNDLE" orchestration task-list --run <run_id> --json
"$ORCA_BUNDLE" orchestration gate-list --json
```

### 판A — `conductor-core-contract-1` / `run_01553b7a106b`

- 감독 터미널: `term_0575ba65-3f3c-4f96-ae38-2a06a148d1a0` (`~/Dev/conductor-core`, gpt-5.6-sol medium)
- 카드: 완료 80 · dispatched 2 · ready 1 · failed 2
  - `INT-1-PREMERGE2 최신 병합 직전 검증` (도는 중)
  - `INT-1 통합 — 합격한 브랜치를 main 으로` (ready, 위 검증 합격 대기)
  - 중계기 순찰 (상주 카드 — 실제 작업으로 세지 마라)
- **국면: 판을 닫는 마지막 단계다.** `INT-1-PREMERGE2` 합격 → 감독이 슈퍼에게 보고 →
  **슈퍼가 kyle에게 결정 관문 제출** → 승인 후 순차 병합·전체 시험·독립 통합 검수.
- **origin 병합은 kyle 관문이다. 절대 대신 승인하지 마라.**

**열린 결정 — 이미 kyle이 답한 것 (실행 중)**: `--run` 계약 = **다 안**.
편지 `msg_559528216d09` 에 전문이 있다. 두 문장을 계약에 박아야 한다:
1. 네 번째 값은 **불투명 토큰**이다 — core는 저장하고 되돌려줄 뿐 해석하지 않고, 해석은 발급한
   어댑터만 한다 (A1 커서와 같은 원칙).
2. **필수다.** 실행 묶음 개념이 없는 호스트는 어댑터가 "유일 묶음" 토큰을 정의해 명시한다. 생략 금지.
   이름은 `host_scope` 권장, 최종 명명은 감독 재량.

**사전검증이 찾은 막는 사유 4가지** (편지 `msg_36825aa31df2`):
`--run` 계약 정면충돌(A1·A8 없음 vs A11 필수, 양방향 실측 errors=5 / errors=12) ·
A8 체크포인트 표기 오류(문서 `9972adb`, 실제 `f85d19e`) · **main 기준선이 빨감**(Ran 81 FAILED errors=5) ·
통합 지도 6커밋이라 적었으나 실제 9커밋.

### 판B — `mailbox-relay-1` / `run_7879c26f3598`

- 감독 터미널: `term_ddf1e84f-1103-48de-bab4-e7e7027c2dde` (`~/Dev/kyle-agent-skills`, gpt-5.6-sol medium)
- **Context 82% (실측 22:2x)** — gpt 계열이라 자동 압축에 맡기는 것이 kyle 결정이다. 다만
  압축이 안 일어나 계속 오르면 그때는 교대다. 서로 다른 시점 2회 관측으로 판단하라.
- 카드: 완료 42 · dispatched 1 · ready 2 · failed 9
  - `R-F-B10-2 실행 증인 재설계 독립 검수` (도는 중, 방금 재발령)
  - ready: `B8 감독 주기적 자가 점검 깨우기`, `B11 같은 발령의 두 번째 질문이 감독을 못 깨운다`
- 오늘 이 판이 오전에 **14시간 잠들어 있었다** — 작업자가 어제 일을 끝내고 편지까지 보냈는데
  companion이 죽어 아무도 안 읽었다. 죽은 게 아니라 깨우는 사람이 없었다.

### 미해결 결정 관문

```
0건 (실측: gate-list)
```

---

## 6. 오늘 실사고와 박제 위치

| 사고 | 무엇이 문제였나 | 박제 |
|---|---|---|
| 모델 지정 금지 주입 | opencodex 로케일 버그. 판A 16번 순찰 정체 | `conductor/references/agent-runners.json` · `b7ae2cc` `4f7e9df` |
| 감독이 watch-card를 붙들고 폴링 | **2026-07-27의 재발.** 규칙이 사고 기록에만 있고 임명장에 없었다 | `mechanics.md` · `4129be8`, 템플릿 신설 `5c7cfe4` |
| 판 둘이 동시에 멈춤 | kyle의 "대기열 비우지 않는다"가 표준 어디에도 없었다 | `appointment-template.md` 1b · `c9a5a10` |
| 중계기 교대에 카드 발령 누락 | 중계기는 살아 일기를 쓰는데 장부는 죽은 자리를 가리킴 | `mechanics.md` · `6dac235` |
| 검수자 문맥 독립성 시험 | 자체 검수 0건 / 독립 1건 / 심판 2건. 둘 다 놓친 것 1건 | `tiki-taka.md` · `766293e`, 원본 `conductor-core/.staging/result-EXP-RI-1.md` |
| 죽은 카드 4시간 반 방치 | 신고와 조치 사이에 주인이 없다 | **아직 안 박음 (§3-1)** |

**관통 학습**: `~/Dev/kyle-hub/coding/2026-08-10_규칙이-행위자에게-안-닿으면-없는-것이다.md` (커밋 `e164273`)
— 같은 모양이 하루에 세 번 났다. 규칙을 어디에 적었는지가 아니라 **그 규칙을 실행할 사람이 그 문서를
읽는지**가 문제다.

---

## 7. 다음에 깨어나야 할 조건

| 조건 | 어떻게 알게 되나 | 그때 할 일 |
|---|---|---|
| **판A `INT-1-PREMERGE2` 합격** | 감독이 슈퍼 Run으로 보고 | 결과를 실측 확인하고 **kyle에게 병합 결정 관문 제출** |
| 판B 실패 9장 분류 결과 | 감독 보고 | 진짜 실패와 차단 탓을 갈라 재발령 순서 판단 |
| A11 제외 사유 | 감독이 검증자에게 확인 후 보고 | `다 안` 방향을 흔들면 kyle에게 다시 올림 |
| **부하 1분 ≥ 12 연속 2회** | Monitor 알림(CPU 상위 붙어 옴) | 원인이 우리 판인지 먼저 보고, 아니면 신규 발령만 보류 |
| **메모리 여유 ≤ 25%** | Monitor 알림 | 도는 것까지 멈추고 kyle에게 즉시 보고 (어제 이 방향으로 기계가 죽었다) |
| 상주 companion 0개 | Monitor 알림 | 해당 판 감독에게 자기 pane에서 재기동시킴 (`ORCA_BIN` 필수) |
| 중계기 일기가 20분 이상 멈춤 | `board-status.py` 또는 웹 관제 | 중계기 재가동. 원인 분석보다 재가동이 먼저다 |
| 판의 도는 카드가 0인데 조용함 | 관제 화면 | **주의: "막힘"과 "할 일 없음"은 다르다.** 우편함부터 읽어라 |

### 매일 처음 할 일 (권장 순서)

```bash
# 1) 판 상태 한 화면 — kyle 기본 화면은 웹 관제다
python3 ~/Dev/kyle-agent-skills/skills/orca-conductor/scripts/board-dashboard.py   # http://localhost:8787
#    보조: ~/.claude/skills/orca-conductor/scripts/board-status.py [--watch]

# 2) 슈퍼 우편함 (비파괴)
"$ORCA_BUNDLE" orchestration check --run run_b58669d80d88 --peek --json

# 3) 상주 프로세스 생존
ps -axo pid,ppid,etime,command | grep -E "conductor-companion|opencodex/node_modules/bun" | grep -v grep

# 4) 부하·메모리·스왑
uptime; memory_pressure | tail -1; sysctl vm.swapusage
```

---

## 8. 이 자리에서 지켜야 할 것 (전임자가 오늘 어긴 것들)

- **한 점으로 판정하지 마라.** 오늘 세 번 어겼다 — 스왑("재부팅해야만 비워진다"), Context(80% 한 번
  보고 교대 제안), 부하(1분만 보고 해제). 전부 여러 시점에서 재야 하는 값이었다.
- **읽기 실패를 0으로 뭉개지 마라.** "카드 0개"와 "카드를 못 읽음"은 다르다.
- **짝으로만 성립하는 규칙은 함께 줘라.** "띄우고 잊는다"만 주면 잠들어 안 깨고, "대기열 비우지
  마라"만 주면 깨어서 폴링한다. 오늘 이걸로 판 둘을 세웠다.
- **감독의 장부(카드·발령)를 대신 고치지 마라.** 감독이 단일 작성자다. 어긋남을 찾으면 근거와 함께
  넘겨라.
- **kyle 관문**: push · origin 병합 · 배포 · 삭제 · 마이그레이션 · 그의 앱/프로세스 재시작.
  삭제는 `rm` 대신 `.staging/` 이동이 기본이다.
- **다른 판·다른 세션의 파일을 조용히 덮어쓰지 마라.** 지금 이 저장소에 다른 세션의 미커밋 변경이 있다(§0).

---

## 9. 모름으로 남긴 것

- ~~현재 Monitor의 명령 원문을 못 옮겼다~~ → **해소됨.** 세션 종료 정리 중 `TaskStop` 출력에서
  원문을 확보해 §부록에 그대로 붙였다. 새 세션은 그것으로 같은 감시를 다시 걸 수 있다.
- 판B 감독의 정확한 Context 추이(압축이 실제로 도는지)는 **2회 관측을 못 채웠다.** 82% 한 점만 있다.
- `잠든 판 26개` 각각의 장부-실물 정합성은 **확인하지 않았다.**
- 헤드리스 중계기 vs luna의 **비교 결론을 못 냈다.** 원자료는 판B 일기에 쌓여 있다.
  (`.orca/relay-logs/mailbox-relay-1.relay-log.md` 의 `| patrol |` 줄 = 헤드리스, 나머지 = luna)
  **헤드리스 프로세스는 세션 종료 정리로 껐다**(아래 §10). 원자료는 그대로 남아 있으니 비교는 가능하다.


---

## 10. 세션 종료 정리 (2026-08-10 23:0x)

kyle 지시로 이 세션이 띄운 것만 정확한 PID로 껐다.

| 대상 | 조치 | 근거 |
|---|---|---|
| `relay-patrol.py` PID 36410 (판B 헤드리스 중계기 시험) | **껐다** | 끄기 전 판B luna 중계기가 `live=true`(`term_f6408d4a…`, gpt-5.6-luna)임을 확인 — 감시 공백 없음 |
| 하네스 Monitor `bt2kla2d8` | **껐다** | 세션과 함께 끝나는 것이라 남겨둘 수 없다. 명령 원문은 아래 부록 |
| companion PID 24635 (판B) · PID 53051 (판A) | **남겼다** | 끄면 판이 편지를 받아도 안 깨어난다 |
| opencodex 프록시 PID 57081 | **남겼다** | 모든 codex 작업자가 거친다. 죽으면 502로 작업자가 죽는다 |
| `board_test` companion (PPID≠1) | **안 건드렸다** | 다른 세션의 회귀 시험 |

파일은 하나도 지우지 않았다. 삭제는 kyle 몫이다. 남아 있는 산출물:
`.orca/relay-patrol-headless.out` · `.orca/companion-mailbox-relay-1.out` ·
`.staging/relay-patrol-test-20260810/`

### 부록 — 슈퍼 감시 Monitor 명령 원문

새 세션이 같은 감시를 걸려면 이걸 그대로 쓰면 된다. **`ME` 는 죽은 옛 handle이므로
그 조건은 사실상 안 걸린다.** `run:run_b58669d80d88` 조건만 유효하다(§1 참고) —
새 세션 handle로 바꾸거나 그 조건을 빼도 된다.

```bash
DB="/Users/fw_m1/Library/Application Support/Orca Kyle/orchestration.db"
ME="term_671919bc-5a12-4c2f-9fca-2bec648cd6a4"   # 죽은 handle — 새 것으로 교체 권장
LAST=$(sqlite3 -readonly "$DB" "select coalesce(max(sequence),0) from messages;" 2>/dev/null || echo 0)
PREV_L=init; PREV_M=ok; PREV_P=ok; PREV_C=init; HIGH=0
while true; do
  sleep 30
  CUR=$(sqlite3 -readonly "$DB" "select coalesce(max(sequence),0) from messages;" 2>/dev/null) || continue
  [ -z "$CUR" ] && continue
  if [ "$CUR" -gt "$LAST" ]; then
    sqlite3 -readonly "$DB" "select '[편지 '||case when to_handle like 'run:%' then '판주소' else '내handle' end||'] '||type||' | '||substr(subject,1,105) from messages where sequence>$LAST and (to_handle='run:run_b58669d80d88' or to_handle='$ME') and from_handle<>'$ME' and type<>'heartbeat';" 2>/dev/null
    LAST=$CUR
  fi
  set -- $(uptime | sed 's/.*averages: //' | tr -d ',')
  L1=$(printf '%.0f' "$1" 2>/dev/null); L5=$(printf '%.0f' "$2" 2>/dev/null)
  M=$(memory_pressure 2>/dev/null | grep -o '[0-9]*%' | tail -1 | tr -d '%')
  P=$(ps -Ao pid= | wc -l | tr -d ' ')
  C=$(ps -Ao ppid=,command= | grep "[c]onductor-companion.sh" | awk '$1==1' | grep -o '\-\-board [a-zA-Z0-9_-]*' | sort -u | wc -l | tr -d ' ')
  [ -z "$L1" ] && continue
  [ "$L1" -ge 12 ] && HIGH=$((HIGH+1))
  SL=$PREV_L
  [ "$HIGH" -ge 2 ] && SL=bad
  # 해제는 1분과 5분이 모두 내려와야 한다 — 1분만 보면 5분이 15인데도 풀린다 (2026-08-10 실측)
  if [ "$L1" -le 9 ] && [ -n "$L5" ] && [ "$L5" -le 11 ]; then HIGH=0; SL=ok; fi
  [ "$PREV_L" = init ] && [ "$SL" = init ] && SL=ok
  SM=ok; [ -n "$M" ] && [ "$M" -le 25 ] && SM=bad
  SP=ok; [ -n "$P" ] && [ "$P" -ge 1600 ] && SP=bad
  SC=ok; [ "$C" -eq 0 ] && SC=bad
  if [ "$SL" != "$PREV_L" ]; then
    if [ "$SL" = bad ]; then
      TOP=$(ps -Ao pcpu,comm -r 2>/dev/null | sed -n '2,4p' | awk '{printf "%s(%s%%) ", $2, $1}' | sed 's:/[^ ]*/::g')
      echo "[관문] 부하 1분 $L1 / 5분 $L5 — 연속 2회 정지선 초과. CPU 상위: $TOP"
    elif [ "$PREV_L" = bad ]; then
      echo "[해제] 부하 1분 $L1 / 5분 $L5 — 둘 다 내려옴. 발령 재개 가능"
    fi
  fi
  [ "$SM" != "$PREV_M" ] && { [ "$SM" = bad ] && echo "[관문] 메모리 여유율 ${M}% <= 25%" || echo "[해제] 메모리 여유율 ${M}% — 복귀"; }
  [ "$SP" != "$PREV_P" ] && { [ "$SP" = bad ] && echo "[관문] 프로세스 $P 개 — 폭주 방향" || echo "[해제] 프로세스 $P 개 — 복귀"; }
  [ "$SC" != "$PREV_C" ] && { [ "$SC" = bad ] && echo "[관문] 상주 companion 0개 — 편지가 와도 감독이 안 깨어난다" || echo "[해제] 상주 companion 이 붙은 판 ${C}개 — 정상"; }
  PREV_L=$SL; PREV_M=$SM; PREV_P=$SP; PREV_C=$SC
done
```
