# 공통 장비 (mechanics) — 모든 패턴이 공유하는 실행 절차

일꾼 생성, 배분·감시, 사용량, 정리 — 어떤 판이든 이 절차를 그대로 쓴다. (내장 순찰 run은 사용 금지 — SKILL.md 안전 규칙 7)
왕복·검수·배틀 오프닝은 `tiki-taka.md`, 섹션 분해·섹션 검수는 `standard-flow.md` 참조.

## 1) 일꾼 생성 (2단계 패턴 — 모델/강도 지정의 공식 경로)

```bash
orca worktree create --repo id:<repoId> --name m1-dev-sol --no-parent --json
orca terminal create --worktree id:<full-worktree-id> --title dev-sol \
  --command '<roster.md의 프리셋 명령>' --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json
```

- `worktree create --agent claude|codex`(내장 런처)는 모델 지정이 불가하다. 모델/강도가 중요하면 반드시 위 2단계.
- **worktree 생성 기준 (2026-07-27 Orca 공식 갱신 반영)**: 공식 가이드는 worktree 생성을 "사용자 명시 요청 또는 구체적 checkout·파일 충돌"로 제한하고, 독립 작업·병렬 실행·편의·분리 선호는 격리 사유로 인정하지 않는다. 우리 하네스도 이 기준을 기본으로 따른다 — 같은 랠리의 순차 라운드(구현·수정·검수)는 같은 worktree를 공유하고 새 worktree를 만들지 않는다. 병렬 랠리의 worktree 격리만 "병렬 작업자 간 파일 범위 충돌 위험"이라는 구체적 사유로 허용하며, 그 사유를 카드 설계(파일 범위)에 명시한다. 파일 범위가 완전히 분리된 병렬 작업이라면 새 worktree 대신 같은 worktree에 작업자 터미널을 추가하는 것을 우선 검토한다.
- **브랜치명은 레포 규칙을 따른다 (2026-07-20 위반 재발로 박제)**: Orca `--name`은 표시명 겸 브랜치명이라 짧게 지으면 레포 브랜치 규칙(예: Rottie는 `kyle/<type>/<slug>`)을 위반한다. **워크트리 생성 직후 `git -C <worktree경로> branch -m <표시명> <규칙명>`으로 즉시 개명**하는 것을 표준 절차로 한다 (Orca는 경로 기준 추적이라 개명 무해 — 실측). 각 레포의 브랜치 규칙은 그 레포 CLAUDE.md 기준.
- Claude/Codex 일꾼은 첫 실행 시 폴더 신뢰/훅(Hooks) 프롬프트에 멈출 수 있다: `terminal read`로 확인 후 선택지 전송(훅은 "3. 신뢰 없이 계속" 기본) + `--enter`.
- **훅 프롬프트는 첫 tui-idle 뒤 늦게 뜰 수 있다 (2026-07-15 실측)** — idle 확인 직후 발령하면 프롬프트가 발령문을 삼킨다. 순서: idle 대기 → read로 프롬프트 확인·통과 → **다시 idle 대기** → 그다음 dispatch. 이미 삼켰다면: 프롬프트 통과 → `dispatch --dry-run --return-preamble`로 발령문을 뽑아 `ctx_dryrun`을 `dispatch-show`의 실제 발령 ID로 치환 → `terminal send`로 수동 재배달 (같은 카드 재dispatch는 "active dispatch" 거부됨).
- handle은 create 응답 또는 `terminal list`에서 한 번만 얻고 재사용한다. **단 handle은 라우팅 메타데이터다 (2026-07-27 Orca 공식 갱신)** — Orca 재시작·앱 재연결 뒤에는 pane에 새 handle이 부여될 수 있으므로, 수명주기 판정(worker_done 권한·카드 종결)을 handle 비교로 하지 않는다. 권한의 기준은 `taskId+dispatchId`를 실제 발령된 pane으로 검증하는 것이다. 재시작이 확인되면 `terminal list --worktree <대상> --json`으로 handle을 재해결하고, `terminal_handle_stale`이 보이면 교체 handle로만 계속한다.
- **부팅류 대기에는 시한 3분 기본 (2026-07-21 kyle 지적)**: CLI 부팅은 정상 10~90초. 지휘자가 임시로 거는 "화면 문자열 매칭 대기"(until-loop 등)는 반드시 시한을 달고, 시한 초과 시 화면을 직접 읽어 판정으로 전환한다 — 무시한 대기는 렌더 깨짐(문자 매칭 실패)·스폰 실패 시 영원히 침묵한다(실사고: "❯ Try"가 "❯ Bry"로 렌더돼 매칭 실패, kyle 개입으로 발각). `terminal wait --for tui-idle --timeout-ms`가 있는 경우 그것을 우선 쓰고, 문자열 매칭은 보조로만.

## 2) 배분과 대기

```bash
orca orchestration task-create --spec "<섹션·범위·금지사항 포함 명세>" --json
~/.claude/skills/orca-conductor/scripts/dispatch-safe.sh <taskId> <일꾼handle> <명패handle>
orca orchestration check --wait --types worker_done,escalation,decision_gate --timeout-ms 900000 --json
```

- **표준 발령 시퀀스**: `dispatch-safe.sh`가 `tui-idle` 대기 → 화면 하단의 훅 검토·업데이트·폴더 신뢰 대화상자 확인 → 다시 `tui-idle` 대기 → `dispatch --inject` → polling 기반 스타트 확인을 순서대로 실행한다. 확인창이 남아 있으면 `PROMPT_DETECTED`와 요약을 출력하고 종료 코드 3으로 멈춘다. 자동 통과는 하지 않는다.
- **스타트 판정 계약 (2026-07-24 polling 개선)**: 발령 직전 화면 하단을 베이스라인으로 저장한 뒤, 발령 후 `START_CHECK_INTERVAL_SEC`(기본 5초) 간격으로 polling 하며 `START_CHECK_TIMEOUT_SEC`(기본 120초) 까지 확인한다. 매 poll 에서 baseline 이후 새로 나타난 양성 신호를 **누적**한다. `Esc to interrupt`·`Updated Plan`·`• Ran`·`• Explored` 중 하나 이상의 새 작업 중 신호와 `Context 1~100%` 새 사용량 신호가 **서로 다른 poll 에 관찰돼도** 둘 다 보이면 즉시 `STARTED`(0)다. MCP/SessionStart 부팅 문구가 있으면 `BOOTING` 으로 계속 polling 한다. 확인창이 나타나면 즉시 `PROMPT_DETECTED`(3) 로 종료한다. Context 0%, active 또는 context 단독, 또는 timeout 도달 시 `NOT_STARTED`(4) 와 `dispatch-show --preamble` 확인 안내를 출력한다. **자동 재배달하지 않는다** — 화면 근거를 직접 확인한 뒤 수동 재배달 여부를 결정한다. 운영에서 timeout 은 최소 90초로 clamp 한다 (`DISPATCH_SAFE_TEST_MODE=1` 시 예외). 회귀 테스트는 `scripts/tests/dispatch-safe-test.sh` 로 실행한다. **Context 신호 부재 폴백 (2026-07-27 오판 2건 박제)**: Claude Code 작업자는 "Context N%" 상태바가 없고(codex 전용), 좁은 pane 에서는 "Context…"로 잘려 숫자가 소실된다 — 이때는 서로 다른 poll 에서 **내용이 다른** ACTIVE(스피너 경과·리페인트 변화 = 진행 증거)가 2회 관찰되면 STARTED 다. 같은 내용 반복은 잔상 가드로 세지 않는다. **NOT_STARTED 후속 판정은 luna 위임 가능 (2026-07-27 kyle)**: 감독이 직접 화면을 읽는 대신 중계기(luna)에 "이 터미널이 실제 시작됐는지 화면 근거로 판정, 문제 있을 때만 보고"를 위임해도 된다 — 비싼 감독 기상을 아낀다.
- 스크립트가 실패하거나 수동 배달이 필요한 경우에만 아래 수동 절차를 폴백으로 사용한다: `terminal read`로 하단 확인창을 확인·판단 → 필요 시 처리 → 다시 `tui-idle` 대기 → `orca orchestration dispatch --task <taskId> --to <handle> --from <명패> --inject` → `terminal read`로 양성 신호 확인. 발령문이 삼킨 정황이면 `dispatch-show --preamble`로 발령문을 뽑아 수동 재배달한다.

- **판 식별자 (2026-07-15 kyle 결정)**: 카드 spec은 항상 `[판:<판이름>]` 접두사로 시작한다 (예: `[판:empty-clear] 업체 수정 …`). 장부·우편함이 Orca 런타임 전역 공유라 두 세션이 동시에 지휘하면 다른 판의 카드·보고가 섞여 보인다 — 식별자가 있어야 지휘자가 자기 카드를 즉시 구분하고, 모르는 판의 신호를 오처리하지 않는다.
- **세션별 우편함 주소 (2026-07-15 kyle 결정·실측 정정 — 다중 세션 지휘가 일상)**:
  - **지휘자가 Orca 내부 터미널이면(기본 권장) 자기 자신이 곧 명패다** — 셸에 ORCA_PANE_KEY 등 신분 환경변수가 있고, `dispatch`가 자동으로 자기 핸들을 지휘자 주소로 찍는다(실측: 2026-07-15). 자기 핸들은 `env | grep ORCA`(신분 확인) 후 `terminal list`에서 자기 제목으로 찾는다. 더미 명패 불필요.
  - **외부 셸(Orca 밖) 지휘자만** 더미 터미널 1개를 만들어 그 handle을 명패로 쓰고 모든 `dispatch`에 `--from <명패>`를 붙인다.
  - **지휘자 상주 도우미(표준)**: 현재 `project-supervisor`가 소유한 pane에서 **`ORCA_BIN=<번들 CLI 절대경로>`를 반드시 명시**해(2026-08-10 실측: PATH 자동 탐색은 upstream `orca`로 떨어져 roster를 몰라 `ROSTER_FAIL_CLOSED reason=resolve_failed`로 닫힌다 — 이 환경에서 자동 탐색이 안전한 적은 없다) `scripts/conductor-companion.sh --project <project> --board <board> --supervisor-role <감독-role> --relay-role <중계기-role> --run <project-run> [--super-run <legacy-super-run>] 300`을 Monitor(persistent)로 fire-and-forget 실행한다. `ORCA_TERMINAL_HANDLE`이 role resolve 결과와 다르면 `consumer_owner_mismatch`를 출력하고 exit 4다. companion은 현재 Run `check`·ack와 구조화 mailbox만 읽고, relay·worker·supervisor pane 출력을 읽지 않는다. 구형 handle 위치 인수와 Run 없는 호출은 실패 닫힘한다.
  - **relay patrol 이관**: 별도 relay agent가 supervisor output을 cursor 기준으로 bounded 범위만 읽고 quoted prompt, orchestration render, old scrollback, raw를 거른다. relay는 넓은 후보를 `relay_candidate` 편지(payload의 `taskId`, `dispatchId`, `outputCursor`, `boundedSnippet`)로 project Run에 남긴다. ID 누락·복수 장부·시간 창 모호는 전체 화면을 넘기지 말고 bounded snippet만 relay가 다시 판단한다.
  - **후보와 공식 장부 대조**: companion은 project Run 전체 편지에서 같은 `taskId+dispatchId`의 공식 `decision_gate`·`question(ask)`·`escalation`만 대조한다. 정확히 하나면 `late_recovered`와 wake 0, 없으면 `misrouted_human_decision:<taskId>` escalation 정확히 1회와 supervisor text+Enter 정확히 1회다. 같은 cursor 중복은 wake 0이며, companion이 키워드 예외 목록으로 의미를 최종 판정하지 않는다.
  - relay는 super upper report·kyle 질문·카드 상태 변경을 직접 하지 않는다. kicker는 relay에 도구 실행 줄·Context% 증가, 연속 무진행 2회 정체 보고, bounded 후보 구조화 지시를 보낸다. 교대 기준은 아래 "중계기 교대(handover) 계약"이 최종본이다 — 판단 품질 저하·판 경계·context 80% 초과 셋뿐이고, 여기 있던 "Context 50%" 기준은 2026-08-04에 폐기됐다.
  - **구 방식 폴백**: 상주 도우미를 실행할 수 없거나 고장 난 경우에만 `check --terminal <자기/명패 handle>` + `scripts/watch-inbox.sh <handle>`(run_in_background 직접 실행)를 사용하고, 중계기 순찰은 별도 kicker로 수동 재가동한다.
  - **왜 필수인가(실측 2026-07-15)**: 외부 셸 발령은 자기 신분이 없어 Orca가 지휘자 주소를 **기존 다른 터미널로 대체 기입(fallback)** 한다 — 실측에서 외부 세션 일꾼들의 편지가 전부 내부 세션 지휘자 앞으로 배달됐다(to_handle 원본 확인). `--from` 명패를 쓰면 이 오배달이 사라진다. 배달 자체는 주소대로 정확하다.
  - 그래도 `[판:]` 접두사 + "모르는 카드 불개입" 규칙은 유지 — 명패를 깜빡한 세션·과거 판의 잔재 신호에 대한 마지막 방어선이다.
  - **실행을 멈추는 질문은 편지로, 진행 보고는 터미널로 (2026-07-28 실사고)**: 프로젝트 감독이 지시 수행 중 멈춰야 할 판단(파일 처리·소유 불명·범위 이탈)이 생기면 터미널 출력에만 남기지 말고 **외부 감독 명패로 ask 또는 decision_gate 편지를 보낸다** — 터미널 출력은 아무도 깨우지 않아 조용한 대기가 된다(실사고: 정리 중단 질문이 터미널에만 남아 kyle 육안 발견까지 침묵). 비차단 진행 상황은 기존대로 터미널 보고.
  - **진행 가시성을 감독을 깨워서 사지 마라 (2026-08-10 실사고 — 2026-07-27의 재발)**: 이 항목은 새 사고가 아니라 **재발**이다. 2026-07-27에 같은 실패(감시 스크립트 종료를 기다려 판 정체)를 박제하면서 "감독 임명장 표준 문구에도 같은 줄 포함"이라고 적었는데, **임명장 표준 문구 파일이 존재하지 않았다.** 임명장은 매번 손으로 썼고, 살아 있는 임명장 2장 어디에도 그 줄이 없었다(2026-08-10 실측). 규칙이 기록에는 남고 감독에게는 안 닿은 것이다. → 그래서 `references/appointment-template.md`를 만들었다. **임명장을 발부하기 전에 그 파일의 8개 항목이 문장으로 들어갔는지 센다.** 참조 링크만 거는 것은 통과가 아니다 — 그게 2026-07-27 박제가 실패한 방식이다. kyle이 "판이 뭘 하는지 안 보인다"고 하자 슈퍼감독이 프로젝트 감독에게 "각 단계가 끝날 때마다 터미널 한 줄로 남겨라 — kyle이 그 줄로 진행을 본다"고 지시했다. 감독은 이를 **깨어서 경과를 중계하라**로 받아, `watch-card.sh`를 직접 들고 foreground 대기하며 "5분째 / 7분째 / 8분째"를 출력했다. 반환될 때마다 감독 턴이 하나씩 탄다. 중계기도 companion도 멀쩡히 살아 있는 상태였다.
    - **원인은 감독이 아니라 지시문이다.** "kyle이 그 줄로 본다"는 표현이 감독에게 상시 가시성 책임을 지웠다.
    - **판 상태 확인**: 먼저 `curl -s http://127.0.0.1:8787/status.txt`를 쓴다. 웹 관제 서버가 응답하지 않을 때만 `scripts/board-status.py`로 폴백한다. `board-status.py`는 삭제하지 않는다. 웹 관제가 재사용하는 수집 라이브러리이자 서버 장애 때의 폴백이다. 수집 기준을 고칠 때는 이 파일만 고친다 (기준이 갈라지면 같은 판을 두 화면이 다르게 말한다 — 2026-08-10 Context 교대 문구가 실제로 한 번 갈라졌다).
    - **웹 관제**: `scripts/board-dashboard.py` (기본 http://localhost:8787, 상시용은 아무 터미널에서 실행) — kyle의 기본 관제 화면이다 (2026-08-10 kyle: "웹이 더 편하다"). 사이드바(개요·우편함·터미널·원장 DB·판별 페이지), 카드 사양·결과 펼치기, 편지 보낸이→받는이 이름 풀기, 원장(orchestration.db) 읽기 전용 표 보기까지 담는다. 같은 날 오전의 "웹 대시보드를 안 만든다" 결정은 이걸로 대체됐다 — 당시 우려(서버가 죽으면 화면이 옛 값을 조용히 보여준다)는 화면 상단에 수집 시각을 항상 표시하고, 서버 응답이 없으면 "서버 응답 없음"을 명시하는 것으로 해소했다. 낡은 값이 정상처럼 보이는 경로는 없다.
    - **읽을 수 없으면 '모름'으로 적는다**: 위 스크립트는 `task-list` 실패를 "카드 0개"가 아니라 "못 읽음(0개가 아니라 모름)"으로 낸다. 감시 화면이 실패를 정상으로 보이게 하면 감시가 없는 것만 못하다.
    - **규칙**: 사람의 진행 가시성은 **감독이 아닌 곳**에서 얻는다 — 중계기 일기(`.orca/relay-logs/<판이름>.relay-log.md`)의 갱신, 카드 상태(`task-list`), 터미널 미리보기. 감독에게 요구하는 터미널 한 줄은 **카드가 끝났을 때의 결과 한 줄**이지 경과 중계가 아니다. 지시문에 "kyle이 이걸로 진행을 본다" 같은 문장을 넣지 않는다.
    - **감독의 대기 방식**: 발령 뒤에는 턴을 끝내고 잔다. `watch-card.sh`는 `run_in_background`로 띄우고 **대기하지 않는다**(전부 종결되면 스스로 끝나며 깨운다). watch-card·watch-terminals 실행과 "정상이네" 판정은 중계기 몫이다(§중계기). 감독이 그것을 직접 드는 것은 중계기가 죽었을 때의 임시 조치이며, 그때도 첫 행동은 **중계기 재가동**이다.
  - **외부 감독 프로그램이 있어도 보고 주소는 프로젝트 감독 handle로 둔다.** worker_done·escalation·decision_gate는 프로젝트 감독이 먼저 처리하고, 외부 감독에는 전체 완료·치명 오류·반복 실패·프로젝트 간 충돌·kyle 결정 관문만 올린다. 외부 감독은 판 인계 후 단독 작성자 권한을 침범하지 않는다.
  - **실제 기상 연결**: companion은 새 중요 신호마다 현재 `project-supervisor` role을 resolve해 얻은 handle에 `ORCA_INBOX_WAKE` 텍스트를 보내고 Enter를 별도 전송한다. 외부 프로그램을 깨우는 방식은 하네스별 어댑터가 companion의 `SIGNAL` stdout을 소비한다. 신호 출력만 존재하는 상태를 end-to-end 기상 성공으로 간주하지 않는다.
  - **구형 lifecycle 보고 실패 복구 (`[LEGACY READ-ONLY]`, 2026-07-31)**: 같은 lifecycle 명령을 무작정 재시도하거나 현재 명령으로 번역하지 않는다. relay/worker는 구조화된 보고만 남기고, companion은 mailbox의 구조화 편지만 대조한다. Delivery ack·text+Enter 실패는 fail-closed로 재생하고, 그 밖의 관찰 실패는 warning+continue로 남긴다. companion과 relay는 Run을 자동 인수하거나 카드·Dispatch 상태를 바꾸지 않는다.
  - **사용자 대화 비차단**: 외부 감독 프로그램에서는 `check --wait`, 장시간 `terminal wait`, 60초 단위 반복 poll을 foreground로 실행하지 않는다. 상세 감시는 companion·중계기에서 돌리고 외부 감독은 즉시 반환되는 snapshot 1회만 읽는다.

- `check --wait`는 한 번에 메시지 하나를 돌려준다. 일꾼 N명이면 N번 대기 루프.
- **worker_done 자동 완료 (2026-07-27 Orca 공식 갱신)**: 유효한 `worker_done`(활성 `taskId+dispatchId`, 작업자 자기 터미널 발신)은 카드와 dispatch를 런타임이 자동으로 completed 처리한다. 지휘자가 뒤에 `task-update --status completed`를 붙이지 않는다. `task-update`는 명시적 복구(일꾼 사망 후 수동 종결, ready 재배정, 실패 정정)나 재정의에만 쓴다.
- **worker_done 발송 실패 — 원인은 macOS `timeout` 부재였다 (2026-07-28 실사고 3회, 원인 실측 정정)**: 작업자들이 발송에 자체 시간제한을 걸려고 `timeout 45 orca orchestration send ...`를 썼는데 **macOS에는 GNU timeout이 없어 `command not found`로 즉사**했고, 이게 "런타임 타임아웃"으로 오보고됐다 (Orca 앱 응답 지연 증거는 0건). 규칙: (1) 작업자 카드 spec에 "orca 발송 명령에 `timeout` 래퍼 금지 — macOS엔 없다. 제한이 필요하면 없이 실행" 포함 (2) 발송 실패 시 **오류 원문을 그대로 보고**하고(요약·재명명 금지) 30초 뒤 1회 재시도, 그래도 실패면 판정 전문을 화면에 남기고 종료. 감독은 카드가 dispatched인데 작업자 화면에 완료 판정이 보이면 유실로 판정해 화면에서 전문을 확보하고 `task-update --status completed --result`로 수동 종결한다 (relay의 worker_done_missing 절차와 연동).
- **읽음 소비 없는 확인 (2026-07-27 추가)**: `check`·`check --unread`는 미확인 메시지를 반환하면서 읽음 처리한다. relay·순찰·외부 감독이 "확인만" 할 때는 `check --peek`(미확인, 소비 없음) 또는 `check --all`(전체 이력, 소비 없음)을 쓴다. 낡은 CLI가 `--peek`을 거부하면 `--all`로 받아 미확인만 걸러 본다. 카드 목록 스윕은 `task-list --brief --json`(spec 160자 축약, `spec_truncated` 표시)을 **강제**한다(2026-07-27 kyle 승인 — FULL 1회 = 27.6KB 실측). spec 전문이 필요하면 목록 전체가 아니라 해당 카드만 집어 조회한다 — 장부가 수백 장 쌓인 상태에서 전체 spec을 매번 읽으면 출력이 수백 KB로 불어난다.
- **우편함 어긋남 주의 (2026-07-13 실측)**: 외부 셸에서 발령하면 preamble의 보고 주소가 워크트리의 기본 셸 터미널(아무도 안 읽는 우편함, 이후 stale)로 박힐 수 있다 — 이러면 `check --wait`는 영원히 빈손이다. **감시는 check 단독 금지**: `task-list`의 카드 상태 + `inbox`(전 수신인 조회) 폴링을 병행한다. 카드가 completed인데 check가 조용하면 inbox에서 worker_done을 직접 읽으면 된다(영구 보관이라 유실 없음).
- **표준 감시 스크립트 동봉**: `~/.claude/skills/orca-conductor/scripts/watch-card.sh <taskId> [taskId...]` — 카드 상태 기반, 전부 종결되면 스스로 종료해 지휘자를 깨운다. 반드시 run_in_background로 **직접** 실행한다 (셸 안 `&` 금지 — 부모 종료와 함께 죽음, 실측). 시한/간격은 `WATCH_DEADLINE_MIN`(기본 60)·`WATCH_INTERVAL_SEC`(기본 30)로 조절.
- **순찰 에이전트(patrol)**: 판에 일꾼 터미널이 3개 이상이거나 30분 이상 걸리는 장기 카드가 돌 때 편성한다. `codex-luna-high` 터미널 1개를 쓰며, 레포 루트에서 실행해도 되고 워크트리는 필요 없다. 순찰 카드 spec: `[읽기 전용] 5분 주기로 지정 터미널들을 읽어 진행중/정체/사망을 판정한다. 근거는 도구 실행 줄과 Context% 증가만 인정하고 스피너는 인정하지 않는다(2026-07-19 사고). 같은 활성 터미널에서 진행 증거가 2회 연속 없으면 정체로 보고한다. 명확한 오류·확인창·프리징·프로세스 종료는 첫 발견에 즉시 보고한다. 정상 진행은 통신기록에만 남기고 발신하지 않는다. 지휘자의 판 종료 지시까지 반복한다.`
  - 역할 분담: `scripts/watch-terminals.sh`는 알려진 오류 문구를 토큰 0으로 감시하고, 순찰은 판단이 필요한 정체를 저비용 `luna-high`로 판정한다. 비용 원칙은 조용한 감시이며, 이상일 때만 발신한다.
  - **감시 대상은 자기 판 터미널만 (2026-07-23 kyle 지시)**: watch-terminals.sh든 순찰이든 감시 대상 handle은 **자기 `[판:]`의 일꾼 터미널로 한정**한다. 다중 지휘 세션이 일상이라, 다른 판 터미널을 감시하면 두 지휘자가 같은 죽은 턴에 이중 개입(양쪽 재개 지시·이중 재발령)하는 사고가 난다. 모르는 판 터미널에서 오류 신호가 보여도 불개입 — 기존 "모르는 카드 불개입" 원칙의 감시판 적용이다.
- **터미널 오류 감시**: 판 세팅 때 목록 파일 1개(권장: `/tmp/orca-watch/<판이름>.list`)를 만들고, 감시 프로세스 1개를 `scripts/watch-terminals.sh --list <목록 파일>`로 띄운다. 목록 파일은 한 줄에 handle 하나를 적고, `#` 주석과 빈 줄은 무시한다. 매 주기 파일을 다시 읽으므로 새 handle은 첫 성공 읽기에서 베이스라인을 잡은 뒤 그 다음 새 오류부터 감시하고, 목록에서 뺀 handle은 즉시 감시·베이스라인·실패 기록을 폐기한다. 파일이 없거나 비어도 대상 0으로 조용히 계속 돌며 시한은 계속 센다. 이후 터미널을 만들거나 정리할 때는 목록 파일에 handle을 추가·삭제하기만 하면 되고 감시를 재시작하지 않는다. 발령 묶음이 끝난 직후 목록 파일이 현재 판 일꾼과 일치하는지 1회 확인한다. **목록의 의미는 '활성 카드가 배정된 터미널'이다 (2026-07-23 kyle 발견 박제)**: 카드를 완료하고 다음 라운드를 대기하는 유휴 터미널은 목록에서 빼고, 수정 카드를 발령하는 순간 다시 넣는다 — 안 빼면 순찰이 정당한 유휴를 정체로 오판해 거짓 escalation을 보낸다(실사고: tab-simplify 판 dev 2개 오판). 기존 하위 호환 방식인 `scripts/watch-terminals.sh <handle> [handle...]`도 사용할 수 있다. 오류 감시는 `orca terminal read --json`의 `result.terminal.tail` 최근 4~6줄에서 찾으며, 직전 주기에 없던 새 매치만 `ERROR <handle> <문구>`로 출력하고 종료한다. 터미널 소실은 `GONE <handle>`, 시한 초과는 `DEADLINE_REACHED`로 알린다. 기본 주기는 90초이며 `WATCH_INTERVAL_SEC`(60~120 권장)와 `WATCH_DEADLINE_MIN`으로 조절한다. 반드시 run_in_background로 직접 실행한다 (`&` 금지). 감시 대상은 자기 판 터미널만 유지한다.
- **발령 후 스타트 확인 (2026-07-15 kyle 결정)**: dispatch 1~2분 뒤 `terminal read`로 일꾼의 턴이 실제 시작됐는지 확인한다. **판정 기준은 양성 신호만**: "작업 중/Esc to interrupt 표시" + "Context 사용량 > 0". 프롬프트 화면이 안 보인다는 이유만으로 시작으로 판정하지 말 것 (실측 오판 사례: 업데이트 프롬프트가 늦게 떠 발령문을 삼키고 self-update로 세션 종료 — 화면엔 아무 프롬프트도 안 남아 시작처럼 보였음). 삼켰으면 위 재배달 절차로 복구.
- **Codex 업데이트 프롬프트 주의**: 기본 하이라이트가 "1. Update now"라 발령문 끝의 엔터가 닿으면 그대로 self-update 후 세션이 죽는다. 처리할 땐 숫자 대신 **방향키로 Skip을 하이라이트한 뒤 엔터**.
- 위 스타트 판정 계약은 이 절의 최종 기준이다: 발령 전 베이스라인보다 새로 나타난 작업 중 신호와 `Context 1~100%`가 함께 있어야 `STARTED`이며, 잔상·Context 0%·단일 신호만 있으면 `NOT_STARTED`다.
- **장기 카드 정체 판정 — 스피너는 증거가 아니다 (2026-07-19 실사고, 2026-07-24 kyle 5분 순찰 결정)**: codex 턴이 내부 오류로 조용히 깨져도 Working 스피너는 계속 돈다(50분 무활동 실측, watch-card는 카드가 dispatched라 침묵). 진행 증거는 (a) 화면의 도구 실행 줄(`• Ran`/`• Explored` 등)이 이전 5분 순찰 대비 **증가**했거나 (b) Context % **증가**, 둘 중 하나만 인정한다. Context 파싱 실패('?')는 통과 사유가 아니다. 첫 순찰에서 진행 증거가 없으면 관찰 기록만 남기고, **5분 간격 2회 연속** 진행 증거가 없으면 약 10분 정체로 보고한다. 명확한 오류·확인창·프리징·프로세스 종료는 연속 횟수를 기다리지 않고 즉시 보고한다. 정체 후 복구는 지휘자가 ESC → `task-update --status ready` → 재발령 순서로 판단한다(같은 터미널은 활성 dispatch가 물려 "already has an active dispatch"로 거부되므로 **새 터미널**에 발령).
- **gjc 수동 배달은 표준 스크립트 사용 (2026-07-20 사고 2회 재발로 박제)**: `scripts/deliver-preamble.sh <handle> <발령문파일>` — 텍스트 전송 후 엔터·제출 판정·재시도(최대 3회)까지 자동. 제출 판정은 발령문 "꼬리 24자"가 화면 하단에 남았는지로 한다 (머리 마커 기준 판정은 입력창 스크롤 때문에 오판 — 실사고 2회). 수동으로 할 때도 같은 기준.
- **gjc 일꾼은 `--inject` 불가 (2026-07-17 실측)**: Orca가 gjc를 에이전트 CLI로 인식 못 해 "no recognized agent detected"로 거부한다(맨 셸 주입 방어). 수동 배달 절차: (1) `dispatch --task X --to <handle> --from <명패>` (inject 없이 — 발령 컨텍스트는 정상 생성) → (2) `dispatch-show --task X --preamble --from <명패> --json`으로 발령문 추출 (**dispatch-show도 외부 셸에선 `--from` 필수** — 없으면 sender 판정 실패) → (3) `terminal send --text "발령문"`으로 배달하되 **다중 줄이면 `--enter`가 줄바꿈으로 먹히므로 텍스트 전송 후 제출 엔터를 별도 `terminal send --enter`로 보낸다** (2026-07-18 실측). 제출 판정은 스피너가 아니라 **입력창(composer)에서 발령문 텍스트가 사라졌는지**로 한다 — 기동 직후엔 엔터가 씹히고도 스피너가 보일 수 있다(2026-07-18 재실측, 씹혔으면 엔터 재전송). 이후 worker_done 보고·카드 종결은 정상 작동한다.
- **codex 0.144.5+ 훅 검토 게이트 (2026-07-18 실측)**: 새 codex 터미널은 "21 hooks need review" 다이얼로그가 기동 한 박자 뒤에 떠서 발령문을 삼키고 CLI를 죽일 수 있다. ESC로 닫아도 재기동마다 다시 뜬다. **확정 해법: 일꾼 시작 명령에 `--dangerously-bypass-hook-trust`를 추가**(공식 자동화용 플래그 — 훅이 전부 kyle의 omo/Orca 훅이라 소스 검증 전제 충족). 화면 판정 시 "hooks need review" 문구가 스크롤백 잔상일 수 있으니 반드시 화면 하단 몇 줄 기준으로 본다.
- **gjc 세션 자연사 복구 (2026-07-18 실측, 하루 2회)**: gjc는 장시간 판에서 소리 없이 죽고 시작 화면(로고/세션 목록)으로 재기동하는 패턴이 있다. 화면에 스피너·입력창 없이 로고만 보이면 사망 판정. 같은 터미널 재배달은 금지(시작 화면이 입력을 무시한다). 표준 복구: `task-update --status ready` → 새 gjc 터미널 생성 → **새 dispatch 컨텍스트로 정식 재발령**. 옛 컨텍스트인 채 새 터미널로 배달하면 발령 컨텍스트가 옛 pane에 묶여 worker_done이 "sender_not_assignee"로 거부된다 — 이미 작업이 끝난 경우에만 화면에서 판정 전문을 확보해 지휘자가 `task-update --status completed --result`로 수동 종결한다. gjc 상태 판정은 영어 "Working"이 아니라 **스피너 문자(⠋⠙⣾ 등)** 기준 — gjc는 한글 상태 문구를 쓴다.
- 일꾼이 조용히 죽었을 때(한도 소진 등): `orca orchestration task-update --id <taskId> --status ready` → 다른 일꾼에게 `dispatch --inject` 재배분. (이 재배분은 자동이 아니다 — 지휘자가 감지하고 실행해야 한다.)
- **복구 국면에도 편성 규칙은 그대로다 (2026-07-28 실사고 박제)**: DISPATCH_FAILED·죽은 터미널·재발령 실패 등 복구 중이라도 새 작업자·검수자는 반드시 `select-routing-pair.sh` + roster 프리셋으로 편성한다. **roster에 없는 CLI(opencode 등)를 임의 생성하는 것 금지** — 실사고: 감독이 발령 실패 2회 후 라우터 없이 미등록 opencode를 검수자로 생성 (내부 모델은 어차피 등록된 GLM이라 얻은 것 없이 절차만 위반, 감독 자인). 복구가 급할수록 절차가 무너진다 — 급한 국면일수록 라우터 한 번이 더 싸다.
- **기존 터미널 재발령 전 생존 확인 (2026-07-20 사고 2회 박제)**: `dispatch --inject`는 대상 pane에 살아 있는 CLI가 있는지 재검증하지 않는다 — 죽은 터미널이면 발령문이 **맨 셸에 명령으로 주입**된다(실측 2회, zsh parse error로 무피해였지만 임의 명령 실행 위험). 기존 터미널에 발령하기 전 반드시 **별도 호출**로 `terminal read`를 떠서 화면 하단에 에이전트 TUI(상태바·입력창)가 있는지 확인한다. 셸 프롬프트(`%`, `$`)가 보이면 죽은 것 — 같은 터미널에 CLI 재기동(같은 handle이라 dispatch 컨텍스트 유효) 후 `dispatch-show --preamble` 수동 재배달로 간다. 이미 주입했다면: git status 무결성 확인부터. **주의: `terminal send --interrupt`는 작업 중 턴엔 중단이지만 idle codex엔 세션 종료로 동작한다(실측)** — 검수 종결 후 잔여 턴 정리에 interrupt를 썼다면 그 터미널은 죽었다고 가정하고 재발령 전 생존 확인을 건너뛰지 마라.
- **GUI QA의 외부 키 입력 대상 고정 (2026-07-24 실사고)**: Rottie QA 작업자가 macOS `System Events`를 써야 하면 `rottie-gui-qa`의 외부 키보드 입력 안전 계약을 카드에 포함한다. `first process whose frontmost is true`처럼 현재 맨 앞 앱에 보내는 fallback은 금지한다. QA 시작 때 기록한 정확한 process name·PID와 입력 직전 `frontmost=true`를 모두 재검증하고, 하나라도 다르면 입력하지 않고 실패로 보고한다. Rottie QA 앱과 Codex·Orca·터미널·브라우저를 구분하지 못하면 중단한다.

## 조사 카드 계약 (2026-07-15 kyle 결정 — 탐색은 카드로)

원인을 모르는 상태에서 시작하는 탐색(원인 추적·코드 서칭·DB 실측)은 지휘자가 직접 하지 않고 조사 카드로 배분한다. 몇 개 파일 읽으면 끝나는 단순 대조만 지휘자 직접 허용 (SKILL.md 안전 규칙 6).

- 프리셋: roster.md의 조사 편성. 터미널은 해당 레포의 메인 워크트리(레포 루트)에 띄워도 된다 — 코드 변경이 없으므로 격리 불필요.
- 카드 spec 필수 요소: `[읽기 전용 — 어떤 파일도 수정 금지, 커밋·push 금지]` + 조사 질문 + 실측 의무(추정이면 '추정' 명시) + 보고 형식: **원인 / 근거 파일:줄 / 영향 범위 / 수정 옵션 2~3개**.
- 종결: 검수 루프 없음(티키타카는 구현 전용). 지휘자가 보고의 근거 파일:줄을 직접 대조 확인하고 종결. 조사 결과가 파괴적 결정(삭제·마이그레이션·초기화)의 근거면 2차 의견 카드 1개 추가.

**라우팅 원장 자동 기록 (2026-07-27)**: `select-routing-pair.sh`(편성 선택)·`dispatch-safe.sh`(발령)·companion(worker_done)이 원장을 자동 append 한다 — 감독 수기는 검수 판정·랠리 총평만 남고, 체크포인트 커밋 턴에 같이 쓴다 (`references/routing-observability.md` 2층 구조). 판 세팅 시 dispatch-safe에는 `ROUTING_BOARD=<판이름>`을, companion에는 명시적 `--board <판이름>`을 전달한다. companion은 `ROUTING_BOARD`가 비어도 현재 `--board`를 `worker_done_auto` 원장에 그대로 전달하며, board 누락·불일치만 Delivery 소비 전에 fail-closed하고 그 밖의 관찰 오류는 warning+continue로 남긴다.

## 사용량 확인 레시피

```bash
# ChatGPT/Codex 폴백 복귀 probe (2026-07-22 kyle 승인 박제): 폴백 편성으로 도는 판에서는
# **매 발령 전** 아래 스크립트 1회로 원 편성 복귀 가능 여부를 기계 판정한다 (md 문장만으로는 누락됨 — 실사고 2026-07-22).
# exit 0=복귀 가능 / 2=쿼터 소진(폴백 유지) / 3=라우팅 오류 / 4=기타. 유휴 터미널 상태바는 갱신 안 되므로 판정 근거로 쓰지 않는다.
~/.claude/skills/orca-conductor/scripts/probe-codex.sh
# Claude/Codex/Kimi/GLM: Rottie 하단 수집기가 사용자 전용 원장으로 자동 내보낸다.
# gjc: gjc stats (Codex 쿼터와 별개)
# 숫자는 "쓴 비율"(100 근접 = 소진)이며, 라우터는 제공자별 20분 이내 최신값만 사용한다.
~/.claude/skills/orca-conductor/scripts/select-routing-pair.sh \
  --task-size heavy --experiment-key '[판]:카드명'
# → 선택된 developer/reviewer와 점수·예약선 사유

# 구현·검수 발령 직전: 현재 쿼터와 불능 provider를 넣어 조합 전체를 다시 점수화한다.
# 주간 예약량은 리셋 24시간 전부터 0까지 풀리고, 5시간 1.5배 여유는
# 리셋 1시간 전부터 1.0배까지 풀린다. 출력 reasons에서 적용값을 확인한다.
# Rottie 최신값이 없을 때 OpenCodex는 자동으로 합쳐진다. 아래 파이프 방식도 명시적 입력이 필요할 때 계속 지원한다.
curl -s http://127.0.0.1:10100/api/provider-quotas \
  | ~/.claude/skills/orca-conductor/scripts/select-routing-pair.sh \
      --quota-file - --task-size heavy --experiment-key '[판]:카드명' \
      --unavailable-provider zai
```

<details><summary>구 방식 (비상 대안 — 프록시 다운 시만. 토큰 15분 수명, kimi CLI 최근 실행 시에만)</summary>

```bash
python3 -c "
import json,urllib.request
c=json.load(open('/Users/fw_m1/.kimi-code/credentials/kimi-code.json'))
r=urllib.request.Request('https://api.kimi.com/coding/v1/usages',headers={'Authorization':'Bearer '+c['access_token'],'Accept':'application/json'})
print(json.load(urllib.request.urlopen(r,timeout=10))['usage'])"
```

</details>

## 종료·정리

- 리허설/실험 worktree 정리는 kyle 승인 후: `terminal stop` → `worktree rm --force`(개별 실행, 절대경로 id) → `orchestration reset --all`(그 판의 카드만 있을 때).
- 산출물이 필요한 worktree는 정리 전에 백업 경로를 보고한다.
- **명패·감독 주소 보존**: 판이 살아 있는 동안 명패와 프로젝트 감독 터미널을 중간 정리 대상으로 삼지 않는다. 유휴 작업자·검수자는 감시 목록에서 빼되, 명패·프로젝트 감독·중계기는 판 종료 인계가 끝날 때까지 보존한다. `terminal stop --worktree`처럼 같은 worktree의 모든 터미널을 닫는 넓은 종료는 금지하고, 이번 판에서 만든 정확한 handle·PID만 종료한다.
- **중계기 카드 수명**: relay 초기화가 끝났다는 이유로 카드를 completed로 닫지 않는다. 판이 살아 있는 동안 relay 카드는 dispatched/monitoring 의미로 유지하고, 판 종료 시 companion·중계기 종료와 잔여 자식 확인까지 끝난 뒤 completed 처리한다. 카드 상태와 실제 프로세스 수명이 다르면 오류로 기록한다. **교대할 때는 카드를 새로 만들지 말고 발령만 옮긴다 — "카드는 하나, 발령만 교체".** 실사고 2026-08-10(다른 세션 발견, 슈퍼감독 실측 확인): 중계기 교대로 새 터미널을 세우면서 `assignee_handle` 을 안 옮겨, 카드는 죽은 `term_a36b4fa3…`(terminal_handle_stale) 을 가리키는데 실제 relay 는 `term_a1b3c293…` 에서 live 로 일기를 쓰고 있었다. **중계기가 살아서 일기를 갱신하고 있어도 장부는 틀릴 수 있다** — 일기 mtime 만 보고 정상으로 판정하지 않는다. 교대 절차에 대조 한 줄을 고정한다: 교대 직후 `roster resolve --role relay` 의 `currentHandle` 과 카드의 `assignee_handle` 이 같은지 확인한다. 같은 카드 재dispatch 는 active dispatch 로 거부되므로 `--retry-request` 또는 `task-update --status ready` 로 발령을 푼 뒤 다시 dispatch 한다.

- **codex 일꾼 잔여 프로세스 정리 (2026-07-23 메모리 폭주 사고 박제)**: codex는 살아 있는 동안 MCP 자식을 중복 재생성하고 옛 세트를 방치하는 버그가 있다(한 부모에 92개 실측). 정상 종료 시엔 자식이 같이 죽지만(실측), 일꾼 터미널을 강제 종료·방치하면 자식이 남는다. (1) 발령 명령에 역할별 경량 프로필(기본 `-p orca-worker`)이 있으면 자식이 역할에 필요한 1~2개로 제한되므로 이게 1차 방어다(roster.md 역할별 프로필 표). (2) headless `codex exec`를 직접 띄운 경우 wrapper PID를 기록해 두고, 작업 종결 시 살아 있으면 그 PID 하나에 TERM을 보낸다(자식은 부모 종료 시 동반 종료 — 실측). (3) 판 종료 시 `ps`로 자기 판 일꾼의 잔여 자식(lsp-daemon·codegraph·server.mjs·playwright·context7)을 읽기 전용으로 확인하고, 남아 있으면 kyle에게 목록 보고 후 승인받아 정리한다 — 다른 판·다른 세션의 프로세스는 절대 건드리지 않는다.

- **감시의 생존 관리 (2026-07-23 실사고 박제)**: 감시 프로세스도 죽는다. (1) 재가동 반사 — 감시 작업의 실패/종료 알림을 받으면 내용 분석보다 **재가동을 먼저** 한다 (원인 무관, 판이 살아 있는 한 감시 공백 금지). (2) 세션 복귀 시 감시 3종(watch-card·watch-inbox·watch-terminals) 생존을 점검하고 죽은 것을 재가동한다.

- **중계기 헤드리스 검증 완료 — DeepSeek (2026-08-10)**: 2026-08-07~08 판에서 DeepSeek 중계기 교체가 **승인 창 때문에 두 번 실패**해 Luna로 복귀했고, 그때 "DeepSeek 자체 실패로 기록하지 말고 저비용 중계기는 헤드리스 1회 호출 구조로 따로 검증한다"는 후속을 남겼다(rally-log 2026-08-07~08). **그 검증을 2026-08-10에 실행했고 통과했다.**
  - 명령: `command-code -p '<판정 질문>' --model deepseek/deepseek-v4-flash --yolo --no-session`
  - 실측: 정체/정상 판정 질문 1건에 **6.075초**, 정답, **승인 창 없음**. 예전 실패 원인이던 승인 창은 `--yolo`(권한 프롬프트 우회) + `-t`(프로젝트 자동 신뢰)로 사라진다.
  - `command-code --list-models` 기준 DeepSeek 은 `deepseek/deepseek-v4-flash`(기본)와 `deepseek/deepseek-v4-pro` 둘이다. **opencodex 프록시에는 DeepSeek 이 없다**(13종 중 0) — codex 경유로는 못 쓴다.
  - **구조가 달라진다**: 지금 중계기는 Orca 터미널에 상주시키고 kicker가 5분마다 찔러 깨우는 구조인데(LLM 에이전트가 상주 턴을 못 버티기 때문 — 2026-07-23 실측), 헤드리스 1회 호출이면 **터미널도 kicker도 필요 없다.** 셸 루프가 순찰(커서 읽기·일기 append)을 하고, **판단이 필요한 지점에서만** 모델을 1회 부른다.
  - **아직 안 한 것**: 실제 교체. 중계기는 판정만 하는 게 아니라 watch-card/watch-terminals 실행·일기 기록·편지 발송·프록시 자가 복구까지 맡는다. 판정만 떼어 헤드리스로 옮기는 것이 첫 단계이며, 살아 있는 판에 적용하기 전에 한 판에서 먼저 시험한다.
- **감시 중계기(relay) — luna-low (2026-07-23 kyle 설계)**: 감시 신호를 지휘자(비싼 모델)가 전부 직접 받으면 기상 횟수가 곧 토큰이다. 중계기 luna-low 터미널 1개가 감시를 대신 받아 "중요한가?"를 판정하고, 중요한 것만 지휘자 명패로 전달한다. (1) 편성 기준: **예외 없이 항상 — 판 세팅 표준 절차에 포함** (kyle 2026-07-23 확정: 1장짜리 판은 드물고, 판은 1장으로 시작해 커지는 게 보통이라 예외 조항 자체를 없앰. 실례: qa-allinone 4장→8장+). 명패·watch-inbox와 같은 스텝에서 중계기 터미널을 함께 띄운다. **중계기 편성 명령 (kyle 2026-07-23 — 최경량 프로필)**: `codex -p orca-lean --model gpt-5.6-luna -c model_reasoning_effort="low" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` — 중계기는 코딩을 안 하므로(셸 스크립트 실행·orca 명령·편지 발송뿐) LSP·OMO 플러그인 전부 불필요, 자식 프로세스 0개인 orca-lean이 정확히 맞는다. (2) 중계기 몫: watch-card/watch-terminals 실행·시한 만료 재가동·감시 목록 갱신·진행 확인("정상이네" 판정)·순찰 겸임(위 순찰 절의 luna와 같은 터미널 1개 — 별도 편성 아님). **(2.1) 상주 턴은 성립하지 않는다 (2026-07-23 실측, kyle 발견)**: '판 종료까지 반복하라'고 지시해도 LLM 에이전트는 각 처리 후 턴을 끝내고 잠든다 — 백그라운드 감시가 신호를 내도 처리할 두뇌가 없다. 표준 구조는 **알람 kicker**: 지휘자가 토큰 0짜리 셸 루프(5분 주기, run_in_background)로 중계기 터미널에 '[순찰 알람] ...' 텍스트+엔터를 보내고, 중계기는 알람마다 짧은 턴 1개로 순찰·기록·(이상 시) 보고 후 다시 잠든다. kicker가 죽으면 순찰 공백이므로 지휘자 1시간 기상 때 kicker 생존도 함께 점검한다. **프록시 자가 복구 포함 (2026-07-23 kyle 승인)**: ERROR 신호가 프록시 계열(`stream disconnected`·127.0.0.1:10100 연결 오류)이면 중계기가 직접 `ocx ensure`(미복구 시 `ocx status`→`ocx start`)로 프록시를 살리고, 멈춘 일꾼에게 "이어서 진행" 재개 지시까지 한 뒤 지휘자에게는 무보고. 복구 실패 시에만 지휘자 명패로 전달. (실사고 2회: 2026-07-23 프록시 사망으로 kimi/glm 일꾼 일괄 정지 — kyle 수동 복구) (3) 지휘자 몫으로만 전달: worker_done·escalation·decision_gate·오류 검출·정체 판정. **(3.1) 랠리 파이프라인 공백 감지 (2026-07-27 실사고 박제)**: 순찰 때 자기 판의 랠리별 마지막 카드 상태를 확인해, **구현/수정 카드가 completed인데 후속 검수 카드가 15분(순찰 3회) 이상 만들어지지 않으면** 그 랠리를 공백으로 보고 감독 명패로 escalation 1회 보낸다 (제목: `pipeline_gap:<이슈/랠리>`). 이 유형은 오류도 정체도 아니어서 기존 감시 전부의 사각지대다 (실사고: #79 4R 구현 완료 후 재검수 미발령 — kyle 육안 발견). 오탐 억제: 결정 관문 대기·배치 대기·동시 실행 상한 조절 등 감독이 "의도된 대기"라고 답한 랠리는 상태가 바뀔 때까지 다시 보고하지 않는다. 같은 랠리 같은 공백의 반복 escalation 금지. (3.4) **heartbeat 편지 금지 (2026-07-23 kyle 지시)**: 중계기는 '정상·생존' 신호를 지휘자 명패로 보내지 않는다 — 생존 증명은 통신기록 파일의 갱신 시각(mtime)이며, 지휘자는 1시간 기상 때 mtime으로 중계기 생존을 판정한다. 명패 발신은 이상(정체·미복구 오류·판단 필요)뿐. (3.45) **토큰 소모 기록 (2026-07-23 kyle 지시)**: 순찰 때 각 터미널 상태바의 모델명·Context %·weekly % left를 통신기록 줄에 함께 적는다 — 판 종료 후 모델 효율 분석(rally-log)의 원자료. (3.5) **통신기록 의무 (2026-07-23 kyle 지시)**: 중계기는 자기가 수신한 모든 신호·판정·조치를 **대상 레포 본체의 `<레포루트>/.orca/relay-logs/<판이름>.relay-log.md`**에 append-only로 남긴다(한 줄: 시각|신호|판정|조치 — **시각은 `date "+%Y-%m-%d %H:%M:%S %z"` 형식 고정**, 2026-07-28 실사고: 자정 전환 후 89건이 시·분 없이 기록돼 시간 분석 불능). 다중 레포 오케스트레이션이라 로그는 해당 레포에 붙인다(2026-07-23 kyle 결정). 주의 2가지: (1) 판 워크트리가 아니라 **레포 본체 경로**에 쓴다 — 워크트리는 판 종료 시 삭제됨 (2) 그 레포 .gitignore에 `.orca/`가 없으면 판 세팅 때 추가한다. /tmp 금지(재부팅 소실) — 중계기 카드 spec에 이 의무를 항상 포함한다. (4) 지휘자는 자기 명패 watch-inbox 1개만 유지하되 **반드시 `WATCH_TYPES=worker_done,escalation,decision_gate`로 띄운다** — watch-inbox 기본값은 worker_done 제외(watch-card 몫이라는 구 설계)인데, 중계기 체제에선 지휘자가 watch-card를 안 들므로 기본값 그대로 쓰면 완료 신호를 영영 못 받는다 (2026-07-23 실사고: 카드M worker_done 도착에 지휘자 미기상, kyle 발견). 그리고, 그 시한 만료(1시간 1회)를 중계기 생존 점검 겸용으로 쓴다(중계기 사망 = 감시 공백이므로 이 보험 기상은 수용). (5) 지휘자 기상 절약 3칙 (kyle 2026-07-23 — **중계기 없는 판에서만 적용**): 진행 확인 타이머는 본 작업이 먼저 끝나면 TaskStop으로 취소(유령 알림 방지) / 확인류는 다음 실제 작업 턴에 얹어 처리(타이머 남발 금지) / 마지막 1~2건 국면에서는 완료 알림 외에 아무것도 안 건다. **중계기가 있는 판에서는 이 3칙이 불필요하다** — 감시가 깨우는 대상이 luna라 비용 전제가 사라지므로, 막판에도 감시를 줄이지 않고 풀 커버리지(오류·정체 감시 포함)를 유지하는 것이 기본이고, 타이머 정리·얹어가기는 중계기의 내부 위생 규칙로 내려간다 (kyle 2026-07-23 확인).

  - **중계기 강도 최신 우선 규칙 (2026-07-31 kyle)**: 이 절 앞부분의 `luna-low` 명령은 2026-07-23 당시 기록으로만 남긴다. 새 판의 실제 중계기·순찰 기본값은 `codex -p orca-lean --model gpt-5.6-luna -c model_reasoning_effort="high" --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust`다. 같은 신호를 두 번 확인해도 판단이 불확실할 때만 세션 안에서 xhigh로 임시 승급하고, 정상 순찰에는 xhigh를 쓰지 않는다.
  - **중계기 중복 금지·신호 누락 복구 (2026-07-24 실사고)**: 정상 `worker_done`은 작업자·검수자→프로젝트 감독의 직접 우편이 원본이므로 relay가 같은 완료를 `worker_done`으로 다시 보내지 않는다. 감독의 감시 대상 갱신 `status`는 읽고 relay log만 갱신하며 “확인했습니다” 답장을 보내지 않는다. 카드가 completed인데 직접 worker_done이 없으면 60초 유예 후 전역 inbox에서 같은 taskId+dispatchId 직접 신호를 다시 확인한다. 그래도 없을 때만 `escalation` 제목 `worker_done_missing:<taskId>`로 한 번 보고한다. 정상 완료 복제, status 답장, 같은 누락 escalation 반복은 금지한다.
  - **중계기 교대(handover) 계약 (2026-08-04 교대 실패 박제 — SKILL.md 안전 규칙 8의 상세)**:
    - **언제 교대하나 — 셋뿐이다.** (1) 판단 품질 저하 (2) 판 경계 (3) context **80% 초과**. 그 전에는 **압축이 기본**이다. 예전 "Context 50%에서 교대" 기록은 남겨 두되 현재 기준이 아니다 — 교대 자체가 감시 공백 위험을 만드는 작업이라, 압축으로 버틸 수 있으면 교대하지 않는 쪽이 싸다.
    - **교대 기준은 모델 계열마다 다르다 (2026-08-10 kyle 결정)**: 이 예외는 **gpt 계열만** 해당한다.

      | 계열 | 상주 역할에서 | 80% 도달 시 |
      |---|---|---|
      | gpt (codex: sol·luna·terra) | 자동 압축이 잘 돈다 | **교대하지 않는다.** 압축에 맡긴다 |
      | 그 외 (claude opus·fable, zai glm, kimi k3) | 자동 압축을 기대하지 않는다 | **교대한다.** 80% 부근에서 인수인계를 준비한다 |

      gpt 계열에서 교대를 제안할 근거는 **(a) 판단 품질 저하가 실제로 보일 때 (b) 판 경계 (c) 80%를 넘긴 뒤에도 압축이 안 일어나 Context가 계속 오를 때** 셋뿐이다. **한 번 읽은 80%는 근거가 아니다** — 서로 다른 시점의 관측 2회에서 계속 오르는 것을 확인한 뒤에 올린다(2026-08-10: 슈퍼감독이 한 번 읽은 80%로 교대를 올렸다가 취소).

      비-gpt 계열을 감독·중계기 같은 **상주 역할**에 앉힐 때는 이 차이를 편성 단계에서 미리 계산한다 — 판이 길면 교대가 반드시 한 번 들어간다.
    - **순서는 고정이다.** `후임 생성 → 공식 roster 등록 확인 → 기동 확인 → 실제 순찰 1회 확인 → 그다음 선임 정지`. 등록 확인은 `roster list`/`roster show`에 후임이 실제로 나오는 것이고, 순찰 확인은 후임이 relay 로그에 자기 판정 줄을 1회 append 한 것이다. **화면에 CLI가 떴다는 것은 어느 단계의 증거도 아니다.**
    - **후임 없이 선임 종료 금지.** 위 단계 중 하나라도 확인되지 않으면 교대를 실패로 기록하고 선임을 그대로 유지한다. 실패를 "일단 후임이 떴으니 됐다"로 반올림하지 않는다 (실사고 2026-08-04: 후임 생성·화면 시작은 확인됐지만 roster 미등록·`RELAY_SUCCESSOR_READY` 부재 상태에서 교대로 판정될 뻔했다).
    - **인계는 무상태다.** 넘기는 것은 `cursor` + append-only relay 로그 경로 + `project`/`board`/`run`/`super-run` 뿐이다. 선임의 대화 문맥, 판단 이력, 요약 브리핑을 넘기지 않는다 — 후임은 로그와 cursor에서 스스로 상태를 복원해야 하고, 그래야 선임의 오판이 그대로 상속되지 않는다.
    - **relay-role kicker의 죽은 handle resolve 실패는 warning+continue.** kicker가 이미 사라진 handle을 resolve하지 못해도 kicker를 죽이거나 재기동 반사를 걸지 않는다. 같은 실패가 반복되면 사실 한 줄만 감독에게 보고한다(원인 추정·조치 제안 없이). fail-closed 대상은 Delivery ack와 text+Enter 실패뿐이라는 기존 원칙 그대로다.

  - **제품 결함 A·B와 임시 운영 (2026-08-04 확정 — 공식 relay 복구 전까지 유효)**:
    - **결함 A — 등록 실패가 조용히 숨는다.** `terminal create --role`은 같은 identity에 active 레코드가 있으면 roster 등록을 건너뛰면서도 `ok=true` receipt를 돌려준다. receipt에 등록 여부 필드가 없어 호출자가 확인할 방법이 없다. 실측 경로는 Orca 저장소 `src/main/runtime/orchestration/role-roster-creation.ts:117`(사전 검사가 기존 pane 재사용 때만 동작)·`:127-138`(늦은 실패를 `console.warn`으로 삼킴)·`src/cli/handlers/terminal.ts:163-186`(receipt에 registered 없음). 제품 수정 요구(fail-closed 또는 명시 경고 + receipt `registered`)는 Orca `docs/TODO.md` 5번에 있다.
    - **결함 B — 고쳤지만 실행 중인 앱에는 없다.** roster rebind는 구현·독립 검수 PASS까지 끝났지만(`8544dbdd7`), 지금 도는 운영 앱 바이너리는 `ee610730d` 기준이라 rebind가 들어 있지 않다. 실측: 배포된 `app.asar`에서 rebind 고유 마커 `new_pane_available`·`old_pane_confirmed`·`record_still_active` 각 0건, 기존 roster 마커 `single_active_candidate`는 4건. 즉 roster 기능은 있고 rebind만 없다.
    - **금지.** 두 결함을 우회하려고 `orchestration.db`를 직접 고치지 않는다. 그 밖의 추가 우회도 만들지 않는다. 우회는 결함을 숨겨 다음 판에서 같은 사고를 되풀이하게 한다.
    - **임시 운영.** `term_f0c5cb34-6f03-4d76-aeef-b7b6556a0994`는 **공식 relay가 아니다.** 비등록 순찰 보조로만 굴리고, relay 로그 줄과 status 보고에 **비공식임을 매번 표시**한다. 공식 relay의 권한(교대 대상, 공식 신호 발신원)을 갖지 않는다.
    - **companion 생존 확인.** companion PID 90191의 생존을 주기적으로 확인하고, 죽어 있으면 즉시 상위에 보고한다. 비공식 보조가 companion을 대신할 수 없다.
    - **공식 relay 복구 시점.** rebind가 실제 운영 앱에 실린 다음에 한다. 그 교체는 Orca `docs/TODO.md` 4번의 **동기화·빌드 판 첫 실전 사례**로 예약돼 있다 — 별도 임시 빌드로 앞당기지 않는다.

  - **`auth.openai.com/oauth/token` 복구 (2026-07-24 실사고)**: 이 문구를 Kimi·GLM provider 장애로 기록하거나 곧바로 Terra·Sol로 재발령하지 않는다. Codex 하네스 OAuth 장애로 기록하고, relay가 같은 터미널의 TUI 생존을 확인한 뒤 30초→90초→180초 점증 간격으로 최대 3회 복구한다. 매 시도 전에 `codex login status`와 `ocx doctor`를 실행한다. 둘이 정상이면 같은 터미널에 `이어서 진행`을 보내고 새 도구 실행 또는 Context 증가를 확인한다. 진단이 계속 실패하거나 같은 OAuth 오류가 3회 반복되면 더 재시도하지 않고 프로젝트 감독에게 `codex_oauth_unavailable` escalation을 한 번 보낸다. `codex login`은 브라우저 재인증이 필요할 수 있으므로 자동 실행하지 않는다. 같은 Codex 하네스 안의 모델 교체는 우회가 아니며, 필요하면 감독이 Codex가 아닌 하네스로 전환한다.
