---
name: rottie-conductor
description: Kyle's Rottie 자체 오케스트레이션(파일 프로토콜) 지휘 하네스. orca-conductor의 규칙·패턴(카드 설계, 티키타카, 승급 사다리, 검수 계단, 안전 규칙)을 그대로 상속하되, 명령층만 Rottie 파일 프로토콜로 바꾼 어댑터판. kyle이 "로티로 지휘", "로티 오케스트레이션 테스트", "/rottie-conductor"라고 할 때 사용. Rottie 앱 실행 + 대상 워크스페이스 폴더 열림이 전제.
---

# Rottie Conductor — 로티판 지휘 어댑터

## Why

Rottie에 자체 오케스트레이션(M1~M9)이 구현됐다. Orca 없이 Rottie만으로 지휘하는 날을 위해,
검증된 지휘 규칙(orca-conductor)은 그대로 두고 **명령층만** 로티 파일 프로토콜로 치환한다.

## 상속 (규칙은 전부 orca-conductor 것을 그대로 쓴다)

다음은 `~/.claude/skills/orca-conductor/`에서 그대로 상속한다 — 이 파일에 다시 적지 않는다:

- 안전 규칙(push 금지·관문·지휘자 직접 코딩 금지·조사 경계선) — `SKILL.md`
- 엔진 카탈로그·발탁(구현 폴백 kimi→glm→terra·effort·검수 sol·쿼터) — `references/roster.md`
- 왕복 루프·라운드 사다리·검수 규칙·배틀 오프닝·쪼개기 기준 — `references/tiki-taka.md` / 섹션 분해 — `references/standard-flow.md`
- 카드 설계 원칙(범위·금지·합격 기준·검증 비용 규칙·실물 표면 의무)
- 사고 기록 원칙 — 새 사고는 orca-conductor의 `references/incident-log.md`에 함께 적는다 (지휘 지식은 한 곳에)
- **에이전트 실행기(codex·omo·claude) 실행법·필수 플래그·검증법** — `conductor/references/agent-runners.json` (호스트 무관 공통. Rottie 도 같은 파일을 본다)
- **기록 보고 규칙** — 기록했다고 보고할 때는 `<파일 경로>:<줄> — <누가 언제 읽는가>`를 함께 적는다. `박았습니다`만 쓰면 받는 쪽이 실재·적용 여부를 확인할 수 없다 — `SKILL.md`

## 어댑터 — Orca 명령 ↔ Rottie 파일 프로토콜

**구조 차이 핵심**: Orca는 중앙 런타임(앱 프로세스)에 CLI가 소켓 RPC로 붙는 구조(그래서 "Orca is not running"이 뜬다).
Rottie는 **서버 없이 워크스페이스 안 파일이 곧 시스템**이다:

```text
<workspace>/.rottie/orchestration/
├── events.jsonl        ← 카드·메일의 유일한 원장 (append-only JSONL)
├── .append.lock        ← OS 배타 잠금 (쓰기 전 반드시 획득)
├── claims/             ← 카드 선점 표식 (<task-id>.ready / .claimed)
└── delivery_claims/    ← 메일 배달권 잠금
```

| 지휘 동작 | Orca (orca CLI) | Rottie (파일 프로토콜) |
|---|---|---|
| 장부 확인 | `orchestration task-list` | `events.jsonl`을 읽어 카드 상태 재구성 (원장이 유일 기준) |
| 카드 생성 | `task-create --spec` | 카드 이벤트 1줄을 `.append.lock` 잠금 하에 append (스키마: 프로토콜 문서 "카드 스키마") |
| 발령 | `dispatch --to --inject` | 파일 발령 요청(M5) 작성 → 앱이 준비 상태 판정(M3) 후 PTY 주입(M2). 맨 셸 방어·워크스페이스 상한 4·공정 대기 30초 내장 |
| 보고 수신 | `check --wait` / `inbox` | 메일 이벤트(`worker_done.v2` 등)를 원장에서 읽음. 2비트 규칙(delivered/read) |
| 상태 감지 | 지휘자 수동(스피너 함정) | 앱 내장: OSC 파서 + 하단 리전 판정 + 30초 재스캔 + TTL 10분 + PTY 종료=failed + 15분 무진전 escalation (주의: 스피너 오인 구멍은 TODO 미해결) |
| 보드 | 없음 (CLI뿐) | `OrchestrationBoard` UI (표 뷰) |

**정확한 스키마는 즉석에서 지어내지 말 것** — 카드·메일·발령 요청의 필드는
`<repo>/docs/orchestration-file-protocol.md`가 단일 진실이다. **지휘 전 반드시 해당 섹션을 읽고 그대로 따른다**
(카드 스키마 / 카드 상태 전이 / 파일 발령 요청 스키마 / 메일 스키마와 2비트 규칙 / worker_done.v2).

## 안전 수칙 (로티판 고유)

1. `events.jsonl`은 append-only다 — 수정·삭제 금지. 손상 시 `.corrupt` 보관본도 삭제 금지.
2. `.append.lock` 잠금 없이 원장에 쓰지 않는다 (동시 쓰기 손상 방지). 잠금 획득은 프로토콜 문서 "추가 잠금과 손상 복구" 절차.
3. `claims/`는 파생 표식이지 DB가 아니다 — 지휘 판단은 항상 원장 기준.
4. 실사용 워크스페이스에서 리허설하지 않는다 — 테스트는 전용 임시 워크스페이스 폴더로.
5. **브랜치명은 대상 레포의 규칙을 따른다 (2026-07-20 위반 재발로 박제, orca-conductor mechanics와 동일)**: 워크트리·브랜치를 어떤 수단으로 만들든(Rottie 앱 내 생성 포함) 생성 직후 브랜치가 레포 규칙명(예: Rottie는 `kyle/<type>/<slug>`)인지 확인하고, 아니면 즉시 `git -C <워크트리경로> branch -m <현재명> <규칙명>`으로 개명한다. 개명은 체크아웃·작업에 무해(실측).

## 첫 테스트 시나리오 (kyle 온보딩용)

1. Rottie 앱 실행 → 임시 테스트 폴더(예: `~/Dev/rottie-orch-test`)를 워크스페이스로 연다.
2. Rottie 터미널 세션을 1개 띄운다 (AI CLI 프로필 권장 — 준비 상태 판정 대상).
3. 지휘자(외부 Claude 세션)가 프로토콜 문서를 읽고 단순 카드 1장(예: "README.md에 한 줄 추가")을 원장에 생성 → 파일 발령 요청 작성.
4. 앱이 주입하는지, 보드에 카드가 보이는지, worker_done이 원장에 기록되는지 확인.
5. 결과·마찰을 orca-conductor `incident-log.md`에 기록 — 이 실측이 어댑터 완성도를 정한다.

## 프로비저닝 공백 주의 (2026-07-20 kyle 실측)

- M1~M9는 "이미 열린 터미널"에 대한 발령·보고만 지원한다 — **터미널·워크스페이스를 밖에서 만드는 통로가 없어** kyle이 앱에서 손으로 열어야 했다 (Orca의 worktree/terminal create에 해당하는 것 부재).
- **M10(외부 터미널 프로비저닝 요청)**이 이 공백을 메우는 중 — 완성되면 지휘자가 원장에 프로비저닝 요청 이벤트를 써서 터미널을 만들 수 있다. M10 병합 전까지는 수동 프로비저닝(앱에서 AI CLI 프로필 터미널을 미리 열기)이 전제다.

## 현재 상태 (2026-07-20, 첫 실측 반영)

- 실전 검증 1회 (2026-07-20, 상세는 orca-conductor incident-log 같은 날짜 항목): 파일 카드 생성 → `dispatch_requested`(worktree) → 4초 만에 선점·worktree 생성·PTY 주입·`dispatched` 확정까지 실측 성공. M7 안전망 3종(15분 정체 escalation, PTY 종료=failed, 배달 서킷브레이커)도 실제로 울리는 것 확인.
- 미해결: 워커 codex가 미착수 정체(25분 CPU ~0, rollout 미생성) — 신규 worktree 경로의 codex 신뢰 게이트 또는 발령문 Enter 미제출로 추정. 외부 지휘자는 워커 PTY 화면을 읽을 수 없어 원인 확정 실패. 다음 테스트 전에 codex 신규 경로 신뢰 처리부터 확인할 것.
- 감시 시작 조건: 앱이 해당 워크스페이스에 오케스트레이션 명령(보드 열기 등)을 1회 실행해야 watcher가 뜬다. 앱이 다른 프로젝트를 보고 있으면 원장이 완전히 무시된다(원장 물변화 + claims 미생성이 외부 판별선).
- 지휘자 헬퍼: `scripts/append-ledger.py` — 잠금 획득·sequence 부여·찢어진 줄 처리·fsync까지 규약대로 수행. 카드/발령 요청/메일은 이걸로 1줄씩 넣는다.
- codex 워커 착수 외부 판별선: `~/.codex/sessions/` rollout 파일 생성 + CPU 시간 증가.
- Orca 지휘가 여전히 기본. Rottie 지휘는 kyle이 명시할 때만.
