# 랠리 데이터 대장 (rally-log) — 모델 선택 최적화용 축적 데이터

이 파일은 사람이 읽는 회고·해석 원본이다. 모델 점수 계산용 기계 원본은 각 레포의 `.orca/routing-events/<판>.jsonl`이며 계약은 `routing-observability.md`, 스키마는 `routing-events.schema.json`을 따른다. 이 파일의 서술형 관찰을 자동 점수로 직접 파싱하지 않는다.

## Why

모델·강도 선택을 지금은 시간/횟수 감각으로 하고 있다. 이 대장은 **오류의 종류(치명/중요/사소)·횟수·수렴 기울기·전환 이벤트(재설계, 모델 교체)의 효과**를 랠리 단위로 축적해, 나중에 "어떤 성격의 작업에 어떤 편성이 실제로 수렴이 빨랐나"를 데이터로 판단하게 한다. (2026-07-20 kyle 지시)

## 기록 규칙

- **지휘자는 랠리가 종결(합격·동결·이관)될 때 항목 1개를 append한다.** 진행 중 판은 "진행 중" 표기로 먼저 적고 종결 시 갱신해도 된다.
- 모르는 값은 추정하지 말고 `미상`으로 적는다. 추정이면 `(추정)`을 붙인다.
- 검수 판정 수치는 검수자 worker_done 원문 기준. **검수 범위(델타/전체)와 강도를 반드시 함께 적는다** — 발견 수는 검수 범위·강도의 함수이기도 해서, 범위가 바뀐 라운드의 발견 증가를 "역행"으로 오독하면 안 된다.
- 형식은 아래 스키마를 따르되, 라운드 표는 간결하게.

## 스키마

```
### <날짜> <판 이름> — <레포> <작업 한 줄>
- 성격: <동시성/보안/CRUD/문서/UI/...> · 무게: <LIGHT/HEAVY>
- 라운드: RN <종류: 구현/수정/재설계> <구현 모델-effort> → 검수 <모델-강도, 범위> : <치명·중요·사소>
- 전환 이벤트: <모델 교체/재설계 전환/범위 조정 — 라운드와 효과>
- 결말: <합격/동결/이관/실용 마감> (총 N라운드)
- 관찰: <다음 편성 판단에 쓸 교훈 1~3줄>
```

---

## 데이터

### 2026-07-19~20 rottie-tab-blank — Rottie 터미널 탭 전환 빈 화면 (desired-size resize 상태 기계)

- 성격: 동시성(race)·렌더링 · 무게: HEAVY
- 라운드: 패치 누적 접근 ~10라운드(구현 luna-max) 수렴 실패 → 정책 재설계 ~3라운드 수렴 실패. 검수 sol-xhigh 8회(회당 15~65분, 매회 전체 범위 — 비용 과다의 주 원인으로 판정됨).
- 전환 이벤트: 접근 전환(패치→재설계)에도 병리 조건 race는 미해소.
- 결말: 실용 마감 — 실환경 재현 극히 드묾 판정, 병리 race 6건 TODO 이월 (총 ~13라운드)
- 관찰: (1) luna는 동시성 결함을 반복적으로 놓침 — "모델 능력 부족" 케이스의 대표 실측. (2) max 강도는 서브에이전트 폭주·정체를 유발(luna-max 검수). (3) 매 라운드 전체 범위 재검수가 비용 폭발의 주범 → 델타 재검수 규칙(2026-07-20)의 근거.

### 2026-07-20 원문자 글리프 판 — Rottie 터미널 원문자(①⑧) 크기 널뜀

- 성격: 폰트/렌더링(실물 표면) · 무게: LIGHT→상향
- 라운드: 5라운드 (R1 구현 → R2 수정 → R3 수정(지휘자 WebKit 실측 발견 인용) → R4 수정 → R5 글리프 재설계 medium×HEAVY). 구현·검수 모델 세부 미상(장부 기준 R5가 재설계 카드). 최종 HEAVY 검수 합격.
- 전환 이벤트: R5에서 재설계(글리프 1칸 재설계) 전환 — 이것이 최종 해결.
- 결말: 합격 (총 5라운드)
- 관찰: 실물 표면(렌더된 픽셀) 검수가 코드 검수가 못 잡는 발견을 2회 냄 — 표면 작업엔 실물 증거 의무가 유효.

### 2026-07-20 open-api 판 — modoo-auth-backend #51 외부 연동 오픈 검색 API (모두써티)

- 성격: 보안·쿼터 계약(API 게이트) · 무게: HEAVY
- 지휘: kimi(외부 세션) · 구현: kimi(Low/High) → glm(gjc glm-pro) → terra(xhigh) → terra(high) · 검수: sol(high → xhigh 1회 → medium)
- 라운드(검수 판정): R1 치명1·중요7·사소2(sol-high, 전체) → R2 0·4·2(sol-high, 전체) → R3 0·4·2(sol-high, 델타) → R4 0·3·2(sol-high, 델타) → R5 0·0·1(sol-high, 델타) → R6 0·2·0(sol-high, 델타) → R7 0·2·0(sol-high, 델타) → R8 0·2·0+문서(sol-xhigh, 전체) → R9+R10 0·0·0 **합격**(sol-medium, 델타)
- 전환 이벤트: (1) 모델 교체 kimi→glm→terra — 구 승급 규칙(당일 v2로 폐지) 시절 자동 승급. 치명·race는 해결됐으나 잔여는 계약 정합류라 모델 효과는 혼재. (2) **R8 소형 재설계**(pageSize 기본값·상한 서비스 단일화 + 재파싱 장식자 제거) — 3라운드 연속 회귀(클 clamp→0x10 우회)를 낳던 3곳 중복 처리를 구조로 제거, 이후 계열 회귀 소멸하고 2라운드 만에 종결. (3) 스킬 v2~v4(승급 폐지·검수 xhigh 폐지·medium 고정)가 판 도중에 적용됨.
- 결말: 합격 (총 10라운드: R1 구현 + R2~R10 수정/재설계)
- 관찰: (1) 치명(API 키 로그 유출)은 R2에서 즉시 소멸, 이후 발견은 계약 정합·경계 입력류로 계단 수렴. (2) pageSize 3곳 중복 처리는 패치 3회가 회귀를 재생산 — 재설계 전환이 유효했다(M10 관찰 재확인). (3) 검수가 매 라운드 새 소수 발견을 내는 구간이 김 — 발견이 정합류로 좁아지면 계약 명문화+구조 단일화로 닫는 것이 패치 반복보다 빠르다.

### 2026-07-20 rottie-m10 — Rottie 오케스트레이션 M10 외부 터미널 프로비저닝 (진행 중)

- 성격: 동시성·crash 복구·보안·데몬 통합 · 무게: HEAVY
- 지휘: Fable(외부 세션) · 검수: sol 전담
- 라운드:
  - R1 구현 glm(gjc) → 검수 sol-high(전체): 중요 2
  - R2 수정 glm → 재검수 sol-high(델타): 중요 2 (신규 발견)
  - R3 수정 terra-xhigh(구 규칙의 자동 모델 승급) → 재검수 sol-high(델타): 중요 3·사소 1 — **모델 승급 효과 없음**
  - R4 재설계 kimi-Max(원자적 용량 예약) → 검수 sol-xhigh(전체, 승급 발동): 치명 3·중요 9·사소 4 — 범위가 데몬 파일까지 처음 확장된 검수라 발견 급증(역행 아님)
  - R5 수정 kimi-Max → 검수 sol-xhigh(전체): 치명 1·중요 9 — R4 치명 3 전부 해결 확인, 신규 발견은 데몬 통합부로 이동
  - R6 수정 kimi-Max → 검수 sol-xhigh(전체): 치명 1·중요 10·사소 2 (독립 검수 5개 교차 — 통합부 신규 발견 계속)
  - R7 수정 kimi-Low(새 터미널, v2 속도 우선 첫 적용) → 검수 sol-medium(전체, v4 첫 적용): 치명 1·중요 6 — 검수 12분(xhigh 20~35분 대비)
  - R8 수정 kimi-Low → 검수 sol-medium(전체): 치명 1·중요 2 + "신규 테스트 7종 중 6종 실효성 없음" 지적
  - R9 수정 kimi-Low(테스트 실경로 재작성) → 검수 sol-medium(전체): 중요 2 (치명 0 도달)
  - R10 수정 kimi-Low → 검수 sol-medium(델타): 중요 3 (fd 체인 마무리 부족)
  - R11 수정 kimi-Low → 검수 sol-medium(델타): 중요 2 — 경쟁 테스트가 실제 프로덕션 버그(temp rename 경쟁) 진양성 검출
  - R12 수정 kimi-Low → 검수 sol-medium(델타): 중요 1 (macOS EINVAL 미분류 flaky)
  - R13 수정 kimi-Low(EINVAL 30만회 C 재현 + 추가 프로덕션 결함 발견·제거) → 검수 sol-medium(델타): **PASS 치명·중요 0**
- 전환 이벤트: R3 모델 승급(glm→terra) 무효과 → R4 재설계 전환이 유효(구조 확인 통과 시작). R5에서 kyle 범위 조정 결정(폴백 다중 프로세스 안전은 데몬 2차로 이관) — R5 구현이 데몬 필수 게이트로 선반영. R7부터 v2/v4(구현 Low·검수 medium) 적용.
- 결말: 합격 (총 13라운드, 커밋 1c0ebaab — push는 kyle 아침 결정)
- 관찰: (1) "불합격 반복 → 자동 모델 승급" 규칙의 반례 실측 — 승급(R3)보다 접근 전환(R4 재설계)이 유효했다. 이 실측으로 roster 승급 규칙을 폐지하고 카드 전환 중심으로 개정(2026-07-20 v2). (2) 검수 범위 확장(델타→전체 xhigh)이 발견 수의 지배 변수 — 수렴 판정은 같은 범위끼리 비교해야 함. (3) 통합 경계(앱↔데몬)가 있는 작업은 발견의 전선이 코드→통합부로 이동하며 라운드가 길어짐 — 카드 범위에 통합 상대(데몬 crate) 포함 여부를 초기에 정할 것.

### 2026-07-20~21 open-api-keys 판 — modoo-auth-backend#52 + moducerti-admin-web 오픈 API 키 관리 어드민 (모두써티, 2레포 병렬)

- 성격: 관리자 인증·키 발급 보안 경계 + 신규 관리 화면 · 무게: HEAVY
- 지휘: kimi(외부 세션) · 구현: kimi Low ×2 (랠리별) · 검수: sol-medium (v4)
- 라운드(검수 판정): 랠리A(backend) R1 구현 → 검수 중요 2·사소 1(sol-medium, 전체) → R2 수정 → 재검수 **합격**(델타). 랠리B(admin-web) R1 구현 → 계약 정합 마이크로(지휘자 대조 — todayUsageCount 가정 vs 실제 dailyCounter) → 검수 불합격(상한 불일치·antd 직접 사용, sol-medium, 전체) → R2 수정 → 재검수 **합격**(델타).
- 전환 이벤트: (1) 지휘자가 두 랠리의 계약을 직접 대조해 화면 가정 1건을 검수 전에 정합 — 랠리A 확정 계약을 랠리B에 내리는 마이크로 카드로 처리(재검수 비용 절약). (2) 랠리A의 암묵 정책 상한(100000/100000000)이 랠리B 발견의 원인임을 양쪽 검수 결과로 특정 → 상수+주석으로 명문화.
- 결말: 합격 (랠리A 2라운드, 랠리B 2라운드)
- 관찰: (1) 2레포 병렬 랠리는 계약 가정이 생김 — 지휘자 대조(단순 대조 규칙 허용 범위)로 검수 전 정합이 유효했다. (2) 검수자 부팅 정체(MCP 8/9 반복) 1회 — 닫고 재생성으로 회복. (3) v4(sol-medium 고정) 첫 적용 판 — 발견 품질은 유지되면서 회전은 빨라짐(추정).

### 2026-07-21 rottie-m10 후속 — Rottie 오케스트레이션 M11 프로젝트 등록 + 워크트리 프로비저닝·목록

- 성격: 프로토콜 계약 확장(파일 프로토콜·다중 프로세스·fs 안전) · 무게: HEAVY
- 지휘: Fable(외부 세션) · 구현: kimi-Low(새 터미널) · 검수: sol-medium (v4 고정)
- 라운드: R1 구현 → 검수(전체): 중요 2 (M10 함정 재발 — 경로 기반 open TOCTOU, 프로세스 내 Mutex) → R2 수정(M10 패턴 이식: fd 체인·flock) → 검수(델타): 중요 1 (경쟁 시험이 창을 강제 안 함) → R3 시험 재작성(one-shot 훅) → 검수(델타): **PASS 치명·중요 0**
- 전환 이벤트: 없음 (동일 편성 유지, 3라운드 단조 수렴)
- 결말: 합격 (총 3라운드, 미커밋 — kyle 아침 커밋 결정 대기). M10 13라운드 대비 3라운드로 종결.
- 관찰: (1) 검수 카드에 "직전 랠리(M10)의 함정 목록 재발 확인"을 명시하자 R1에서 정확히 그 부류 2건을 즉시 검출 — **직전 랠리의 발견 목록은 다음 랠리 검수 카드의 체크리스트로 이식할 것**. (2) 수정 카드에 "M10 해법 패턴을 그대로 재사용하라"고 지시하자 R2가 20분대에 정확히 이식 — 해법 재사용 지시가 라운드를 단축. (3) "옛 구현이면 실패해야 한다"는 시험 요구 조건이 위양성 시험 재발(M10 R11~13에서 3라운드 소모)을 1라운드로 압축.

### 2026-07-21 rottie-explorer 판 — Rottie 프로젝트 탐색 패널 UI (디자인 5 orca-operational-strip)

- 성격: 프런트 UI(레이아웃·트리·상태 동기화) + 실물 표면 · 무게: LIGHT(표면 의무 적용)
- 지휘: Fable(외부 세션) · 구현: kimi-Low · 검수: sol-medium (v4)
- 라운드: R1 구현(1h, CDP 캡처 4장) → 검수(전체): 중요 2·사소 2 → R2 수정 → 재검수(델타): 중요 2 (StrictMode 이중 발사·접힌 그룹 미펼침) → R3 수정 → 재검수(델타): 중요 1 (이중 호출 잔존) → R4 소형 재설계(fetch single-flight, 수정 3라운드 소진→접근 전환 규칙 적용) → 재검수(델타): 중요 1 (테스트 증거 공백) → R5 테스트 실단언화 → 재검수(델타): 중요 1 (성공 가드 공백) → R6 useState 래퍼 독립 단언 → 재검수(델타): **PASS 치명·중요 0**
- 전환 이벤트: R4에서 규칙대로 재설계 전환(세대 토큰 패치 → single-flight 구조) — 제품 결함은 그 라운드에서 종결, 이후 3라운드는 전부 "테스트 증거의 실효성" 왕복.
- 결말: 합격 (총 6라운드, 미커밋 — kyle 커밋 결정 대기. 실기동 QA는 kyle 몫 명시)
- 관찰: (1) UI 랠리도 재설계 전환 규칙이 유효 — 비동기 fetch 중복은 토큰 패치보다 single-flight 구조가 정답이었다. (2) 후반 3라운드가 전부 "테스트가 가드 부재를 실제로 검출하나" 왕복 — React 19가 언마운트 setState를 조용히 버려 console 감시가 무력해진 실측 포함. 다음 프런트 랠리 카드에는 "가드류 테스트는 가드 제거 시 실패함을 구현자가 증명(원복 diff 0 포함)" 요구를 처음부터 넣을 것. (3) 검수자가 증거 확인 목적으로 제품 파일을 임시 mutation 후 SHA 원복한 사례 발생 — 검수 카드에 mutation 필요 시 절차(원복+해시 검증)를 명시하는 쪽으로 정리됨.

### 2026-07-21 rottie-devscreen 판 — tauri-dev-screen-cli 실기동 QA 도구 도입 실험

- 성격: 외부 도구 도입(보안 검토·빌드 게이트) + 실기동 QA 자동화 · 무게: HEAVY(보안 경계)
- 지휘: Fable · 구현: kimi-Low · 검수: sol-medium
- 라운드: R1 도입(보안 전수 검토, dev 이중 게이트, 실앱 QA 6/6·캡처 7장) → 검수(전체): 중요 1 (무인증 WS → 로컬 프로세스의 JS→invoke 확대 경로) → **kyle 위험 수용 결정**(개발 전용 + 외부 유출 없음 확인 전제, 인증 요구 철회 — 진행 중이던 인증 카드 지휘자 종결·재발령) → R2 축소판(SHA 고정+재캡처) → 재검수(델타, 판정 기준에 수용 위험 명시): **PASS**
- 결말: 합격 (총 2라운드, 미커밋). 성과: "실기동 QA는 kyle 육안 몫" 관행을 도구로 대체 — 에이전트가 Rottie Dev를 직접 띄워 클릭·캡처·검증 (PID 규칙 준수 실증 2회).
- 관찰: (1) 검수의 보안 발견이 소유자 위험 수용으로 종결되는 첫 사례 — **수용 결정은 다음 검수 카드의 판정 기준에 명시해야 같은 발견 재계상 낭비를 막는다** (실행함). (2) 외부 도구 도입 카드는 "보안 검토 먼저, 위험 시 중단" 구조가 유효 — 검수자가 플러그인 4,681줄 전수 재확인으로 이중 방어. (3) 진행 중 카드의 범위 변경은 interrupt→종결(사유 기록)→새 카드가 깔끔.

### 2026-07-21 open-api-plans 판 — modoo-auth-backend#55 + moducerti-admin-web 오픈 API 플랜(plus/pro) (모두써티, 2레포 병렬)

- 성격: 응답 계약 변경(필드 차등) + DB enum 마이그레이션 + 신규 관리 화면 필드 · 무게: HEAVY
- 지휘: kimi(외부 세션) · 구현: kimi Low ×2 · 검수: sol-medium (v4)
- 라운드(검수 판정): 랠리A(backend) R1 구현(kimi Low, 커밋 b36d4f9) → 검수 중요 1(plan varchar 계약 위반, sol-medium 전체) → R2 수정(PG 네이티브 enum, 544b384) → 재검수 **합격**(델타). 랠리B(admin-web) R1 구현(b9a1e8d) → 검수 중요 1(antd Radio 직접 도입) → R2 수정(공용 radio-group, 6f903a7) → 재검수 **합격**(델타).
- 전환 이벤트: (1) macOS WindowServer 강제 종료로 Orca 데몬이 죽은 세션 자격을 물어 새 터미널이 "login:" 실패 — 앱+데몬 완전 재시작 후 복구 절차(새 명패, ready 리셋, 재생성 재발령)로 유실 0 복구. (2) 구현자가 캐시 키에 plan을 자발 포함 — 플랜 간 캐시 오염을 카드 명세 없이 스스로 방어한 긍정 사례.
- 결말: 합격 (랠리A 2라운드, 랠리B 2라운드)
- 관찰: (1) 이번 판의 두 불합격은 모두 "계약이 코드에만 암묵" 계열(DB enum 미사용, 공용 컴포넌트 미사용) — 카드에 "DB 수준 제약"과 "레포 공용 컴포넌트 우선"을 명시하면 1라운드에 잡힐 수 있었다. (2) 재시작 후에도 장부·워크트리·우편함이 살아 있어 복구 비용이 작았다 — 감시 스크립트만 끊기는 구조.

### 2026-07-21 rottie-tp-refactor 판 — TerminalPanel.tsx 5단계 리팩터링 (3,976→1,966줄, -51%)

- 성격: 대형 파일 책임 분리(동작 불변 4단계 + 동시성 재설계 1단계) · 무게: 단계별 LIGHT, 3단계만 HEAVY
- 지휘: Fable · 구현: kimi-Low(1~4단계) → glm-eco(5단계, Codex 0 전환) · 검수: sol-medium → fable-medium(과도기 1회) → kimi-high(저자 분리)
- 라운드: 1단계(순수 함수 9모듈) 1R 합격 / 2단계(렌더러 훅) 3R — 제품 1R 합격, 이후 2R은 테스트 증거 왕복 / 3단계(세션 훅+resize actor) **6R** — 수정 3R 소진→자동 재설계(3요소 판정 모델: desired·lastKnownPhysical·inflight, 완료는 무시 않고 물리 증거로 흡수)→수정 2R 합격, **이월돼 있던 resize 병리 race 6건 해소** / 4단계(입력 훅, 한글 IME) 2R — 제품 930줄 바이트 동일, 테스트 실효성 1R / 5단계(표시 컴포넌트 7개) 2R — 동작 변경 1건(메뉴 닫기 누락) 검출·수정
- 전환 이벤트: (1) 3단계에서 새 에스컬레이션 사다리(수정3→자동 재설계→수정3→kyle) 첫 실전 작동 — kyle 개입 없이 종결. (2) 판 중간 Codex 소진 → 폴백 3종 실전: fable 과도기 1라운드 → dev glm 전환 → 검수 kimi-high. (3) WindowServer 붕괴로 Orca 완전 재시작 1회(터미널 전멸→재발령 복구).
- 결말: 5단계 전부 합격·단계별 커밋(dc32fd88·d8394f6a·560d286f·4017f94d·6cafa383) — kyle 실기동 QA(한글 입력·붙여넣기·TUI 마우스·탭 왕복) 잔여
- 관찰: (1) "동작 불변" 리팩터의 발견 대부분은 제품이 아니라 **테스트 증거 실효성**에서 나옴 — 후반 라운드의 정형 패턴이므로 카드에 "깨뜨리면 실패 증명" 요구를 1라운드부터 넣는 게 정착됨. (2) 동시성 재설계는 "예외 장치 추가"가 아니라 **판정 모델 단순화**가 수렴 경로였다 (M10 관찰 재확인 — 장치를 늘린 R2~R3은 새 구멍을 낳고, 장치를 제거한 R4가 수렴 시작). (3) 지휘자도 사고를 낸다 — .gjc 무차별 스테이징으로 토큰 push(수습: 세션 종료로 토큰 무력화+amend+force push). 커밋 스테이징도 "파일 지정 add" 규칙을 지휘자 자신에게 적용할 것.

### 2026-07-21 search-keywords 판 — modoo-auth-backend#58 유입 키워드 필터+정렬 (모두써티, 2레포 병렬)

- 성격: 읽기 전용 관리 API 선택적 파라미터 + 어드민 토글 UI · 무게: LIGHT
- 지휘: kimi(외부 세션) · 구현: kimi Low ×2 → (Codex 0 확인 후 규칙 전환) glm-eco · 검수: fable-medium(과도기 1라운드) → kimi-high(저자 분리)
- 라운드: 랠리A(backend) R1 구현(kimi, 6d45220) → 검수(fable, 전체): **치명 1** — sortBy/order 화이트리스트 부재로 식별자 원시 보간 SQL 인젝션(실SQL 재현) → R2 수정(glm, ac6baf5+1843442 — enum 검증+허용 맵 이중 방어, order 방향 잔취 자기 발견 추가 수정) → 재검수(kimi-high, 델타): **합격 발견 0**. 랠리B(admin-web) R1 구현(9ecb361) → 검수(fable): 합격·사소 1(라벨 i18n) → 정정(9ba5c2f, 지휘자 대조 종결)
- 전환 이벤트: 판 도중 Codex 주간 0% 확인 — kyle 신규 규칙(저자 분리: kimi 작업물=fable 1라운드, 이후 glm+kimi-high)이 이 판 실사고로 박제됨
- 결말: 합격 (A 2라운드, B 1라운드+사소 정정). dev-release 머지 후 develop PR #61/#70 머지, dev 배포·실측(정렬 4조합·악성 400·무인증 401) 완료
- 관찰: (1) LIGHT로 분류한 "읽기 전용 선택 파라미터"에서 치명 SQL 인젝션이 나옴 — **문자열 파라미터가 SQL 식별자로 들어가는 카드는 무게와 무관하게 화이트리스트 검증을 합격 기준에 넣을 것** (이번 검수 카드의 기준 4가 잡음). (2) glm이 발령 범위 밖의 잔취(order 방향 보간)를 자기 발견으로 추가 수정 — 리뷰어 발견을 넘어선 방어 심화 긍정 사례.

### 2026-07-21 sec-holes 판 — 무가드 엔드포인트 3종 #48/#49/#50 (모두써티 backend, 이슈별 랠리)

- 성격: 인증 경계(가드 적용·테스트 컨트롤러 삭제) + 남용 방어 · 무게: #48/#49 HEAVY, #50 LIGHT
- 지휘: kimi(외부) · 조사: kimi Low ×2 · 구현: kimi(#48) → glm-eco(#49·#50, Codex 0 조합) · 검수: fable-medium(#48 과도기 1라운드) → kimi-high
- 라운드: 랠리C(#48) R1(kimi, b2424ed) → fable HEAVY **1라운드 합격**(부팅 실측 404·개인번호 0건). 랠리F(#50) R1(glm, f712f18) → kimi-high **1라운드 합격**(실부팅 중복 방지 실측). 랠리D(#49) R1(glm, 0a14332 가드+공개경로) → kimi-high 합격(후속 발견 2: XFF·MIME) → **E(프론트 전환) 검수에서 비회원 경로가 로그인 게이트 뒤임이 드러남** → kyle 결정: 공개 경로 제거·E 폐기 → R2(glm, aa1023c, -605줄) → 델타 재검수(kimi-high) **합격**
- 전환 이벤트: (1) 랠리E 검수가 선행 조사(랠리D 설계 근거)의 오류를 실기동으로 반박 — **조사가 "로그인 전 도달 가능"이라 한 흐름이 실은 게이트 뒤**. 조사 보고도 실물 경로(로그인 게이트 주행)까지 확인하지 않으면 설계가 통째로 흔들린다. (2) 폐기 결정된 랠리(E)는 터미널 즉시 정리·브랜치 보존으로 마무리 비용 최소.
- 결말: 3이슈 전부 합격·dev-release 머지·develop PR #61 머지·dev 배포. 실측: /alimtalk/* 404, /media/* 무인증 401, page-view 동일 IP 2회→+1. 후속 이슈 #59(trust proxy)·#60(MIME 매직바이트) 생성
- 관찰: (1) 조사 카드 2장(호출 지점·소비처)이 설계를 바꿨고(공개 경로 분리안), 검수가 그 설계를 다시 뒤집었다(게이트 발견) — 조사≠실물 확인, 실물 표면 의무가 구조적 결정에도 적용돼야 함. (2) #49처럼 "가드만 vs 공개 경로" 갈림은 비용 큰 설계라, 실기동 경로 확인이 카드 설계 전 선행 조건이어야 한다.

### 2026-07-21 sec-holes 판 연장 — QA 반려 2건 + 키 모달 확인창 + #68 (저녁)

- 성격: dev QA 반려(계약 불일치·토큰 미첨부) + UX 보강 + 세션 인터셉터 결함 · 무게: LIGHT(반려·모달), HEAVY(#68)
- 지휘: kimi(외부) · 구현: glm-eco · 검수: kimi-high (Codex 0 표준 조합 지속)
- 라운드: #58 order 대소문자(QA 반려: 프론트 desc vs 백엔드 DESC) R1 수정(efff104, @Transform 정규화) → 재검수 합격. #49 에디터(QA 반려: CKEditor 생 fetch 토큰 미첨부 401) R1 수정(873e326, 공용 클라이언트) → 재검수 합격. 키 모달 R1(fbfc6d1) → 검수 **치명 1**(ConfirmDialog z-101이 antd Modal z-1000 뒤에 가려져 RemoveScroll 소프트락) → R2(5fb790d, opt-in aboveModal) → 델타 재검수 합격(리그 재현으로 검출력 입증). 랠리G #68 R1(928b879) → HEAVY 1라운드 합격(실 dev 백엔드 403으로 실물 증거)
- 전환 이벤트: (1) 조사 카드(운영 로그 리드온리, kyle 승인)가 세션 사망 사슬 확정 — 서버 무죄, 인터셉터 침묵 삼킴이 범인. (2) 403 JWT_INVALID_TOKEN이 만료의 정식 신호임을 판 도중 발견해 카드에 보강 지시(구현 중 guidance) — 발령 후 발견도 흡수 가능 확인.
- 결말: 전부 합격, dev-release 머지(backend da2d815, admin 317b789·c630b55·13ca509). 일괄 재배포는 kyle 승인 대기
- 관찰: (1) "발급 계약 검증"이 부족하면 2레포 병렬 랠리에서 계약 불일치(asc vs ASC)가 dev QA까지 생존 — 병렬 랠리의 계약은 카드에 리터럴 수준으로 박을 것. (2) 공용 컴포넌트 z-index는 "처음 antd 모달 위에 띄우는 순간" 드러남 — opt-in 승격(aboveModal)이 전역 상향보다 안전. (3) kimi /effort 셀렉터가 직전 선택을 기억해 하이라이트가 들쭉날쭉 — 발령 전 반드시 화면으로 현재 하이라이트 확인 필요(2회 사고).

### 2026-07-22 rottie-popover 판 — 리소스 관리자 팝오버가 터미널 출력에 닫히는 버그 (Rottie)

- 성격: 프런트 이벤트 리스너 예외 1줄 + 회귀 테스트 · 무게: LIGHT
- 지휘: fable(외부 세션) · 조사: kimi Low · 구현: glm-medium · 검수: kimi-high (Codex 0 표준 조합)
- 라운드: 조사(kimi, ~17분) — 원인 확정(xterm viewport scroll이 Popover window 캡처 리스너에 '바깥 스크롤'로 잡힘, 사용처 5곳 전부 영향) + 옵션 3개 → 지휘자 옵션1(최소 침습) 채택 → R1 구현(glm, ~8분: Popover.tsx 예외 1줄+테스트 1건, 전체 487테스트·tsc·build 통과) → R1 검수(kimi-high, ~11분): **1라운드 합격, 발견 0** — 실제 Chromium+xterm 하네스로 수정 전 재현/수정 후 유지 before/after 실측, .xterm 클래스 오포함 없음을 xterm.js 소스로 확정
- 소요시간: 조사 17분 / 구현 8분 / 검수 11분 (라운드 왕복 1회)
- 전환 이벤트: 없음 (배틀 불요 — 조사 권고+Simplicity First로 지휘자 한 문단 결정)
- 결말: 합격. 브랜치 kyle/fix/popover-xterm-scroll (origin/master 기점), 미커밋 — kyle 커밋/머지 승인 대기
- 관찰: (1) glm-medium이 LIGHT 프런트 수정을 1라운드 무결점 통과 — "구현 medium 통일" 정책의 긍정 데이터 1건. (2) kimi-high 검수가 LIGHT인데도 실물 Chromium 하네스를 자발 구축해 before/after 재현 — 실물 표면 의무 문구가 검수 품질을 끌어올림.

### 2026-07-22 rottie-stall-detect 판 — 정체 감지 스피너 오인 구멍 (Rottie, 실사고 기반)

- 성격: 진행 판정 시그니처 교체(출력 seq → 의미 출력 해시) + vt100 의존성 추가 · 무게: HEAVY
- 지휘: fable(외부) · 조사: kimi Low · 구현: glm-medium · 검수: kimi-high (Codex 0 표준 조합)
- 라운드: 조사(3안 평가→(a)권장) → R1 구현(바이트 정규화+합성 fixture, 15분) → R1 검수 **치명**: 검수자가 실물 codex 좀비를 tmux로 직접 캡처(1.13MB)해 리플레이 — 합성 fixture만 통과하는 가짜 안정 적발 → **재설계 전환**(vt100 그리드) → R2 재검수 **치명**: 20분 순수 좀비 신규 캡처(7.2MB)로 256KB 윈도우 헤드 절단 적발 + Claude 스피너 문자 미탐 → R3 수정(persistent 파서 — 증분 투입으로 절단 원천 제거, distinct=1) → R3 재검수 치명0·**중요1(fixture PII 잔존)**·사소4 — static 캐시 수명·동시성·seq 역행까지 하네스 직격 후 안전 판정 → R4 수정(PII 스크럽+사소) → R4 델타 재검수 **합격**(PII 6종 인코딩 스캔 0건, 테스트 변조로 검출력 실증) → 마이크로 문서 정정(지휘자 대조 종결)
- 소요시간: 조사 22분 / 구현·수정 4회 합 ~50분 / 검수 4회 합 ~95분 / 총 ~3시간
- 전환 이벤트: 재설계 1회 — "바이트 정규화→화면 상태(그리드)"로 판정 모델 교체가 전선을 바꿈(rottie-m10 패턴 재확인). 이후 잔여 치명은 표적 수정(persistent 파서)으로 수렴.
- 결말: 합격. 브랜치 kyle/fix/stall-detect-meaningful-hash (M10+master 기점), 미커밋 — kyle 커밋/머지 승인 대기
- 관찰: (1) **검수자의 실물 캡처 능력이 이 판의 품질을 만들었다** — kimi-high가 tmux로 진짜 좀비 세션을 3회 캡처(1.1MB/7.2MB/Claude)해 합성 fixture의 가짜 안정을 두 번 적발. "실물 fixture 의무 + 합성만 통과=불합격" 카드 문구가 유효했음. (2) fixture로 실물 캡처를 쓸 때 **PII 스크럽을 카드 설계 단계에서 미리 의무화할 것** — 검수가 안 잡았으면 개인정보가 커밋될 뻔(이번엔 검수자가 잡음). (3) glm-medium 구현은 방향이 정해진 표적 수정(persistent 파서)에서 강했고, 첫 설계(정규화 규칙 고안)에서 약했다 — 설계 불확실성이 큰 R1일수록 조사·실측 선행이 값어치.

### 2026-07-22 rottie-daemon2 판 — 터미널 데몬 2차 완전판 (Rottie, 카드 4장 순차)

- 성격: 데몬 코어 완성(lease/idle/build_id) + 앱 종료 조정자 + 영속 journal + 기본 켬 전환·패키징 · 무게: 전 카드 HEAVY
- 지휘: fable(외부) · 조사: kimi Low · 구현: glm-medium(카드1~4 대부분), 카드4 후반 **glm-high 승급** · 검수: kimi-high(Codex 0 폴백) → 카드4부터 sol-medium(복귀) → sol 보안필터 차단으로 kimi-high 재폴백
- 카드별 라운드(라운드=dev+review 왕복, 블록=연속 3라운드):
  - 카드1(코어): 구현 → 검수 치명1·중요2·사소7 → 수정 → 재검수 **합격**. 2라운드.
  - 카드2(종료 조정자+팝업): 5라운드 + 재설계 1회. R1검수 치명1(close 인가순서) → 수정 반복 중 '이벤트 emit만 하고 수신 배선 0건' 치명이 **3라운드 연속 재생산**(가짜 배선) → 블록2에서 재설계(커스텀 prepare-quit 프로토콜 폐기 → 보드 기존 close 가드 재사용)로 수렴 → 마이크로 정정 합격.
  - 카드3(journal 최소판): 구현 → 검수 사소6 → 사소정리 → 델타 재검수 → 마이크로 2건. 최단.
  - 카드4(기본 켬+패키징): **7라운드**(블록3까지). 구현 → universal 배선 치명 누적 → **kyle 결정으로 universal 3차 이관(범위 축소)** → 배너 배선/StrictMode/TOCTOU가 순차로 드러나며 블록2~3. TOCTOU 완결이 3라운드 연속 절반수정으로 반려되자 **glm-high 승급**(effort 오분류 정황) → fd 기반 syscall(openat/mkdirat/fchmod/fstat) 전면 전환으로 수렴 → 7라운드 합격.
- 전환 이벤트: (1) Codex 주간 0 폴백 조합(dev=glm+검수=kimi-high)으로 판 시작 → 판 도중 sol 복귀(7/25 예정보다 이른 창) → 검수 sol 복귀 → **sol이 보안필터(cybersecurity)로 TOCTOU/심볼릭링크/토큰 검수 차단** → kimi-high 재폴백(저자분리 충족). (2) **지휘자 probe 누락 사고**: '7/25 갱신 예정' 앵커링으로 폴백 복귀 probe를 판 내내 0회 — kyle 지적으로 발각, probe-codex.sh 박제. (3) opencodex 이관이 codex 전역 라우팅(config.toml base_url 주입)을 바꿔 sol 명령 조용히 깨짐 — 정식 바이너리+base_url 복원 플래그로 우회, roster 박제.
- 결말: 카드 4장 전부 합격, 27파일 +2210/-93 미커밋. 브랜치 kyle/feat/terminal-daemon-round2(M10+master 기점). kyle 커밋/머지 + 실물 QA(실기동 종료 팝업·기본 켬 마이그레이션) 대기.
- 관찰: (1) **glm-medium은 방향 정해진 표적 수정에 강하고 첫 설계·미묘한 보안 완결(TOCTOU)에 약했다** — 카드4 TOCTOU가 medium 3라운드 절반수정 → high 승급 1라운드로 완결. effort 오분류 승급 규칙의 정당 사례. (2) **kimi-high 검수가 판을 지탱했다** — 실물 좀비 캡처(stall판)·dev앱 실기동·실좀비 소켓 실사격을 자발 수행. sol 대비 보안 코드 검수에 제약이 없어 이 판의 보안 하드닝(TOCTOU/심볼릭링크)을 끝까지 검증. (3) '이벤트 emit=배선 완료' 착각이 카드2에서 3라운드 소모 — **프런트-백엔드 이벤트 카드는 검수 기준에 '수신 listener rg 0건이면 치명'을 1라운드부터 넣을 것**. (4) 카드4가 7라운드로 길었으나 발견 심각도 단조감소(치명2→0 유지→중요3→2→1→수용)로 수렴 판정은 명확 — v3 사다리(구현 포함 18라운드 상한)에서 여유 11라운드.

### 2026-07-22 sec-holes 판 랠리H — admin-web#72 폼 검증 trim 일괄 (새벽)

- 성격: 동일 결함(검증 trim 누락)의 전수 일괄 수정 · 무게: LIGHT
- 지휘: kimi(외부) · 구현: glm-eco · 검수: kimi-high
- 라운드: R1(c1cc0c0, 29곳 12파일) → 검수 1라운드 **합격**(사소 1)
- 전환 이벤트: 없음 — 리드온리 전수 조사(지휘자 직접 grep)가 카드의 목록을 확정해 1라운드 종결
- 결말: 합격, dev-release 머지(7a9085d). 배포는 다음 묶음
- 관찰: "한 지점 제보 → 같은 패턴 전수 조사 → 일괄 수정" 흐름이 재보고를 막는다 (폐기/반환 라벨 반전 사고와 같은 계열 — 매핑·검증 로직 복붙 구조의 전수 점검). 이번엔 조사가 명확해서 카드 목록이 곧 diff 대조표가 됨.

### 2026-07-22 rottie-usage-qa 판 — 사용량 키(Kimi ocx/GLM 입력) + xterm QA 훅 (Rottie, 병렬 2랠리)

- 성격: 사용량 collector(외부 HTTP·보안 키 저장) + QA 인프라(dev 전용 훅) · 무게: A HEAVY/LIGHT, B LIGHT
- 지휘: fable(외부) · 조사: kimi(B) · 구현: 랠리A=kimi-low, 랠리B=glm-medium · 검수: sol-medium(정상 복귀, 저자 분리 dev↔review 충족)
- 랠리A(사용량, kimi): A1 Kimi 사용량 ocx 프록시 참조(kyle 방법) 1라운드 **합격**(실측 13%/62% 파싱). A2 GLM 키 설정 UI+저장+collector 3라운드 — R1검수 MEDIUM(Debug 토큰 평문) → R2 custom Debug 마스킹 → R2재검수 MEDIUM(unknown_keys forward-compat 맵 평문) → R3 RedactedUnknownKeys 래퍼 → **합격**. 보안 Debug 누출이 2단(알려진 필드→unknown_keys)으로 드러난 정형.
- 랠리B(xterm QA 훅, glm): 조사(옵션 B: dev 전용 window.__rottieQA 노출, 기존 write_terminal 재사용) → R1 구현 1라운드 **코드 합격**(release 정적 제거 0/dev 2) → 지휘자 실물 검증 **성공**(window.__rottieQA.write('echo QA_HOOK_WORKS\n') → 터미널 실행·출력 확인). rottie-gui-qa 스킬의 xterm 입력 한계 실증적 해소.
- 전환 이벤트: 없음(재설계·배틀 없음). A2만 보안 3라운드.
- 결말: A·B 둘 다 합격. 브랜치 kyle/feat/usage-key-input, kyle/feat/qa-xterm-input-hook. kyle 커밋/머지 대기.
- 관찰: (1) **glm-medium 프론트 표적 가설 긍정 데이터 1건** — 랠리B(TerminalPanel dev 훅) glm이 조사→1라운드 코드 합격+실물 성공, 헤맨 라운드 0. "glm이 방향 정해진 프론트 표적에 강하다"는 지휘자 가설을 뒷받침(단 표본 1, 계속 축적 필요). (2) **kimi-low가 보안 민감 백엔드(A2 키 저장)에서 Debug 누출을 2라운드 놓침** — 알려진 필드는 마스킹했으나 unknown_keys forward-compat 맵을 못 봄. 보안 카드는 kimi-low보다 상위 검수 왕복이 값어치. (3) **지휘자 규칙 오적용 3연발**(폴백 순서·저자 분리를 랠리 간 모델 선택에 오적용 / watch-inbox 판 세팅 누락 / 검수 카드에 소스 수정 요구) — 전부 kyle 지적으로 발각·교정·박제. md 규칙 비강제성이 반복 원인, "명패=watch-inbox 커플링"·검수 카드 소스수정 금지·probe 스크립트로 강제화 진행 중.

### 2026-07-22 api-stats 판 — #63 오픈 API 사용량 통계 (backend+admin-web)

- 성격: 신규 관리자 조회 API 3종 + 통계 화면 · 무게: backend HEAVY, front LIGHT
- 지휘: kimi(외부) · 구현: glm-eco · 검수: kimi-high
- 라운드: 랠리I R1(283e541) → 검수 불합격(치명 1: orderBy alias 비인용 → 실DB summary 500. 목 테스트 체인에 실DB 실행이 없어 탈출) → R2(0bd1edd, 1줄 인용 + 실DB 통합 테스트) → 델타 재검수 합격. 랠리J R1(64585c0) → 검수 중요 1("antd Tabs 컨벤션 이탈") → **지휘자가 스킬 원문 대조해 오보 기각**(admin-conventions: antd 6이 기본) → 합격 종결
- 전환 이벤트: 검수 발견을 지휘자가 스킬 원문으로 기각한 첫 사례 — 과거 전례(Radio 교체)를 과잉 일반화한 오탐
- 결말: 전부 합격, dev-release 머지(backend ed12ca4, admin 7711114). 배포는 다음 묶음
- 관찰: (1) TypeORM orderBy alias는 **반드시 인용** — 목 스파이 스펙은 SQL 문자엧만 보고 실DB 폴ding을 못 잡는다. repository 집계 스펙은 실DB(조걶 스킵) 1개 이상 필수. (2) 검수의 "컨벤션 위반" 주장은 스킬 원문 대조가 1차 필터 — 전례는 문맥을 잃고 일반화되기 쉽다.

### 2026-07-22 rottie-qa-allinone 판 — 잔여 작업 커밋 + 통합 브랜치 + 자동 GUI QA (Rottie, 순차 4카드)

- 성격: 미커밋 마무리(보안 접점) + git 통합(머지 충돌) + GUI 스모크 QA · 무게: A HEAVY / B·C LIGHT / D 조사(QA)
- 지휘: fable(외부) · 구현: glm-medium(A·C·D), 보안 수정만 glm-high 선제 승급(A-R2) · 검수: sol-medium (pace 과속 2.2배로 kimi 몫까지 glm 배분 — 개정 배분 규칙 첫 실전)
- 카드A(usage-keys 미커밋 +480줄): R1 glm "수정 불요" → sol 검수 **치명 1**(unknown_keys가 redact_keys 우회해 IPC 평문 반환 — usage-qa 판과 같은 계열 3번째) → R2 glm-high 수정(IPC clear+RedactedUnknownKeys 이중 봉쇄, 회귀 3종) → 델타 재검수 **합격**(합성 비밀 실측, clear() 부작용 사용처 추적까지). 커밋 d9cf808f.
- 카드B(board-icon 미커밋): 검수 1라운드 **합격**(발견 0). 커밋 a9c6e7fa.
- 카드C(통합 kyle/local/qa-all-in-one): R1 4소스 머지(충돌 6파일) → 검수 **치명 1**(4인자 resolve_credentials에 테스트 호출 12곳 3인자 잔존 — cargo test 컴파일 실패) → R2 수정 → **중요 1**(문서·GLM 합성 토큰 테스트 공백)+사소2 → R3 수정(단언 역방향 자체 확인 포함) → **사소 1**(rustfmt) → micro-fix + 지휘자 대조 **종결**. HEAD c3878379. 심각도 단조감소 수렴.
- 카드D(자동 GUI QA, glm): 5항목 전부 PASS — 상태바 스트립·보드 아이콘 양경로·탐색 패널·__rottieQA 터미널 입력·팝오버 유지. 스크린샷 10장+QA-REPORT.md(/tmp/rottie-qa-all-in-one/), 지휘자 스크린샷 대조 확인.
- 전환 이벤트: A-R2 glm-high 선제 승급(roster 보안 국면 규칙 첫 적용 — 1라운드 완결로 유효). 재설계·배틀 없음.
- 결말: 4카드 전부 합격. 통합 브랜치 kyle/local/qa-all-in-one(c3878379) 완성, kyle 실기동 QA·push·master 머지 관문 대기.
- 관찰: (1) **카드 검증 목록에 cargo check만 넣으면 테스트 컴파일 깨짐을 못 잡는다**(cfg(test) 미컴파일) — 머지·리팩터 카드의 검증은 cargo test --locked가 기본이어야 함. 이번 판 카드C 설계 구멍을 검수가 잡음. (2) unknown_keys 비밀 누출이 3번째 재발(같은 계열) — 검수 카드에 유형을 콕 집어 넣으니 1라운드에 잡힘. 반복 유형은 카드 spec에 전례를 명시하는 게 검출력을 만든다. (3) glm-high 보안 수정 1라운드 완결 — "보안 완결 국면 선제 승급" 데이터 1건 추가(TOCTOU 계열과 일관). (4) 개정 pace 배분(과속→전부 glm) 첫 실전 — kimi 소모 0으로 판 완주, sol 검수 품질 유지.

### 2026-07-23 rottie-qa-allinone 판 확장분 — 탭 재설계·감시 인프라 (랠리 E~H, 전날 판의 연장)

- 성격: E 조사 / F 프론트 표적+레이아웃(HEAVY) / G·H 스킬 감시 스크립트(LIGHT) · 지휘: fable(외부)
- 랠리E(조사, glm): 탭 폭 붕괴·터미널 실종 원인 1방 확정(전 프로젝트 렌더 + rightPanelWidth clamp 부재 + nowrap 넘침) — kyle "많은 프로젝트 미테스트" 가설 적중.
- 랠리F(탭 재설계, kimi→glm 폴백): R1 kimi 구현(429 3연사로 glm 인계 1회 포함) → 검수 REVISE 중요3 → R2~R4 glm 수정 — **중요 3→2→1→0 단조 수렴 4라운드 합격**. 검수(sol-medium)가 매 라운드 실물 재현(900px 폭 실측·재현 순서 실행·설정 SHA 복원)으로 새 구멍을 정확히 1겹씩 벗김: 합산 폭 예산 → 비동기 hydrate 반영 → recent8 backfill. 커밋 535b20b4.
- 랠리G·H(watch-terminals.sh, luna-low 구현): G 3라운드(잔상 오탐→handle별 baseline) + H 3라운드(--list 동적 목록, timeout 예외 흡수·제거 handle 침묵) 합격. **luna-low 구현 데이터 6라운드 축적 — 스크립트 잡일에 충분, 단 엣지(첫 주기 오탐·예외 처리)는 검수가 채움.**
- 전환 이벤트: kimi 429 3연사 → glm 폴백(가용성). glm 429(서버 과열)·프록시 사망 2회·Orca 스폰 고장(재부팅 해결)·세션 재시작 — 인프라 사고가 랠리보다 많았던 판.
- 결말: 판 전체 종결. 통합 브랜치 kyle/local/qa-all-in-one = c3878379(1차 QA 합격분) + 535b20b4(탭 재설계). kyle 실기동 재확인 대기.
- 관찰: (1) **검수의 실물 재현 의무가 4라운드 내내 유효타** — 코드 리뷰만으론 못 잡을 hydrate 경쟁·backfill 구멍을 dev 앱 실측으로 적발. (2) 카드 스펙에 "검수가 재현한 순서 그대로 재실행"을 명시하면 수정-검증 루프가 정확히 맞물림. (3) 감시 인프라(중계기·목록 감시·프록시 자가복구)가 이 판의 사고들에서 역설계됨 — 사고가 곧 설계 입력.

### 2026-07-23 rottie-tab-simplify 판 (진행 중) — 랠리M(terminal-daemon-status 머지) 종결분

- 성격: M 브랜치 충돌 머지+검증(HEAVY) / T 탭 단순화(진행 중) / V·W 지휘 스크립트(LIGHT) · 지휘: gpt-5.5(외부, 세션 교체 1회)
- 랠리M(glm-medium 구현, sol-medium 검수): R1 머지+검증 → 검수 불합격(vitest 게이트 미완주 — sql-wasm.wasm 심볼릭 링크 거부) → R2(vitest.config.ts server.fs.allow 동적 추가로 690테스트 완주 + 들여쓰기 + Ping 테스트) → 델타 재검수 **합격**(치명·중요 0, 사소 4 관찰급). 커밋 9e737641 → master 머지 61c17960 (kyle 관문 통과). feat 브랜치·워크트리 정리 완료, qa 워크트리는 미커밋 5파일로 보류.
- 랠리V(dispatch-safe.sh, luna-low 구현, sol-medium 검수): R1 검수 불합격 중요 2(맨 셸 TUI_IDLE_TIMEOUT, Context 0% STARTED 오인) → R2 수정 완료, 델타 재검수 진행 중. **dispatch-safe.sh 자체가 첫 실전 사용에서 0.03초 즉시 TUI_IDLE_TIMEOUT 오작동 — 지휘자가 수동 dispatch --inject 폴 fallback으로 우회.**
- 랠리W(conductor-companion.sh, luna-low 구현): 검수 1라운드 **합격**(치명·중요·사소 0, 실측 충실) → 즉시 현판 감시를 companion 1개로 교체 가동 (새 표준 첫 실전 적용).
- 전환 이벤트: 세션 교체(handoff 문서 인계) 첫 실전 — 인수인계 문서 + 밀린 신호 확인으로 무중단 재개 성공. 중계기가 유휴 터미널 2개를 정체로 오판(목록 갱신 타이밍) — 발령 예정 터미널임을 지휘자가 알려 취소시킴.
- 관찰: (1) vitest 심볼릭 링크 자산은 server.fs.allow 동적 추가가 정답 — 보정 없이 완주 가능. (2) 검수 스크립트는 만든 판에서 즉시 실전 검증해야 함(구현→검수→실전 사용이 한 판 안에서 순환). (3) handoff 문서의 "즉시 할 일 3줄" 형식이 세션 교체 비용을 최소화함.

### 2026-07-23 rottie-tab-simplify 판 — 랠리V(dispatch-safe.sh) 종결분

- 성격: 지휘 스크립트 신규 · LIGHT · 구현 luna-low · 검수 sol-medium
- 라운드: R1 불합격 중요 2(맨 셸 TUI_IDLE_TIMEOUT, Context 0% STARTED 오인) → R2 불합격 중요 2(화면 잔상 esc to interrupt 오인, mechanics.md:31·50 계약 모순) → R3 불합격 중요 1(파이프 왼쪽에만 붙인 환경변수 → READ_ERROR) → R4(export 수정) **합격**. 중요 2→2→1→0 수렴 4라운드.
- 전환 이벤트: 지휘자가 첫 실전 사용에서 0.03초 즉시 TUI_IDLE_TIMEOUT을 당해 수동 dispatch 폴 fallback — 스크립트는 만든 판에서 즉시 실전 검증되는 구조가 유효.
- 관찰: (1) 셸 파이프 `VAR=x cmd1 | cmd2`에서 VAR은 cmd1에만 적용 — luna-low의 반복 실수 유형 1건 축적. (2) 검수자의 "기존 활성 터미널에 무단 발령 금지" 자기 규율이 실측 설계(스크래치 터미널+더미 카드)를 표준화시킴. (3) mechanics.md 문장과 스크립트 판정을 하나의 계약으로 맞추는 작업은 스크립트 변경과 같은 카드에 넣어야 어긋남이 안 남음.

### 2026-07-23 rottie-tab-simplify 판 — 랠리T(상단 탭 단순화+그룹 트리 이식) 종결분

- 성격: 프론트 표적+레이아웃 · LIGHT(실물 표면 의무) · 구현 glm-medium · 검수 sol-medium
- 라운드: R1 구현(번호순 8개+더보기) → 불합격(900px 클리핑) → R2 클리핑 수정 합격 → R3 그룹 관리 트리 이식 → 불합격(치명: 메뉴 선택자 불일치로 실제 클릭 불가 + 중요: 1440px 탭 숨김) → R4 선택자+ResizeObserver 캡 → 불합격(확대 시 미복구) → R5 폭 계산 수정 → 불합격(가짜 회귀 테스트 — 실제 폭 변경 없이 이름만 리사이즈) → R6 실측형 테스트 교체 **합격**. 중요 2→1→1→0 수렴 6라운드.
- 결말: 커밋 ec3c9da7 → master 머지 7ab592e0 (kyle 관문). 머지 전 master(M 랠리분) 선합치기 무충돌, 머지 후 vitest 690/690·tsc 통과. 워크트리·브랜치 정리 완료.
- 관찰: (1) **스크린샷 확인 ≠ 클릭 확인** — 구현자가 "3동작 스크린샷 확인"이라 보고했지만 실제 pointerdown→click은 메뉴 닫힘으로 전부 불능이었다. 실물 표면 의무는 '실제 입력 이벤트'까지 요구해야 한다(검수 카드에 명시 박제). (2) "테스트 추가함" 보고는 테스트가 실패할 수 있는지로 판정 — jsdom 0폭에서 MAX 8 확인은 회귀를 못 잡는 가짜 테스트. (3) jsdom 리사이즈 테스트는 getBoundingClientRect·clientWidth mock + ResizeObserver 콜백 외부 호출 패턴이 정답.

### 2026-07-25 [판:rottie-daemon3-sync] 진행 중 — 터미널 데몬 3차 동기화

- 성격: 다중 앱 daemon 재접속·복원·Observer·실시간 동기화 · 무게: HEAVY · 지휘: gpt-5.6-sol 프로젝트 감독
- 라운드: M1 9라운드 종결, M2 7라운드 종결 및 체크포인트 `58b64ce6`, M3 구현 진행 중. M4·M5는 아직 미발령.
- 확인된 사실: (1) 같은 입력에서 전체 Vitest와 daemon 통합 테스트가 여러 라운드에서 반복됐다. (2) GUI QA 중 외부 키보드 입력 대상 확인 실패 사고가 있었고, 이후 process name·PID·frontmost 동시 확인 규칙을 적용했다. (3) 2026-07-24 20:14부터 남은 PGID 98122 `tauri:dev` watch 체인이 Rust 변경 때마다 자식 Rottie를 다시 띄웠으며 2026-07-25 00:13 이후에도 새 앱이 생성됐다. (4) 완료·429·OAuth·종료 셸 상태 Orca 터미널 16개가 누적됐고, 완료 M2 QA PGID 65385와 orphan daemon 4개도 남았다. (5) 슈퍼감독 개입으로 PGID 98122, PGID 65385, orphan daemon PID 1755·26450·56180·62342를 정확히 종료하고 유휴 터미널 16개를 handle 단위로 닫았으며 활성 M3 터미널만 보존했다.
- 추정: 반복된 창 재등장의 직접 원인은 M3의 새 앱 실행이 아니라 과거 `tauri:dev` watch 체인이 파일 변경을 감지해 자동 재빌드·재실행한 것으로 판단한다. 프로세스 부모 관계와 생성 시각은 이 판단을 지지하지만, 별도 시스템 추적 로그로 모든 재등장 순간을 1:1 대조한 것은 아니다.
- 운영 교훈: 장기 판에서는 QA 실행 직후 PID·PGID·identifier·runtime-root를 원장에 기록하고, 검수 종료 시 정확한 소유 프로세스와 유휴 터미널을 닫는다. 동일 입력 전체 검증은 재사용하며 실기동은 명시된 QA 단계에서 한 번만 수행한다.
- 결말: 진행 중. M3는 앱 실기동 없이 코드와 focused 검증만 진행하며, 판 종결 시 M3~M5 라운드·검수·체크포인트·라우팅 결과를 이 항목에 갱신한다.

### 2026-07-28 [판:openapi-fix] 랠리 #80 — 오픈 API 키 관리 권한·감사

- 성격: 권한·감사·PostgreSQL migration·동시성 · HEAVY · 구현: Kimi 중심(R1·R2·R6·R7·R8), Opus(R3·R5), GLM(R4) · 검수: Sol medium 기본, 보안 필터 차단 시 GLM high 폴백.
- 라운드: R1부터 R8까지 8라운드. 첫 검수 합격률 0%(R1 불합격), 최종 R8 GLM 독립 검수에서 치명0·중요0·사소0 PASS. 왕복 8회. 정확한 총 소요시간은 원장 자동 이벤트의 시각으로 파생 가능하며 이 줄에는 추정값을 쓰지 않는다.
- 발견 수렴: TypeORM custom repository transaction 500 → append-only 우회(TRUNCATE·수동 script) → verifier의 기존 DB 삭제 위험 → event trigger·실행 문맥 우회 → 운영 관리자 script 가드 → 실패 up 뒤 down의 기존 함수 삭제 → 공개 marker 위조 → TypeORM migration history 권위 + 객체 구조/owner/ACL 교차 검증으로 수렴.
- 전환 이벤트: Sol 보안 검수는 매 라운드 1회 시도했으며 R7·R8에서 `This content can't be shown`으로 차단. 순화·재시도 없이 GLM high로 교체했고, R8에서 history 단독 위조·실패 up·공격 6종을 실제 PostgreSQL 15로 통과했다.
- 결말: 체크포인트 `2016c8555baa10737d85860167f69429503f968d` (`feat(open-api): 키 관리 변경 감사 추가 (#80)`), 19파일. focused 203/203, script 7/7, 전체 447/447, tsc·diff 0, 격리 PostgreSQL 15 PASS. dev-release 합류 대상이며 develop·dev 배포는 #79 완료 뒤 4건 일괄 원칙으로 대기.
- 관찰: (1) 공개 comment marker는 소유권 증명이 아니며 누구나 복제 가능하다. migration history 성공 기록을 권위로 쓰고 marker·owner·ACL·column·trigger·함수 정의를 교차 검증해야 했다. (2) verifier가 실패한 up 뒤 기계적으로 down을 호출하면 복구 도구가 파괴 도구가 된다. 실제 TypeORM `runMigrations/undoLastMigration` transaction 순서를 그대로 검증해야 한다. (3) Sol의 보안 필터 차단은 품질 실패가 아니라 가용성 사건이며, GLM 폴백이 공격 시나리오 검수를 끝까지 수행했다.

### 2026-07-28 [판:openapi-fix] 랠리 #79 — PostgreSQL 기반 분산 분당 제한

- 성격: PM2 다중 작업자 분산 제한·키 회전·429 중복 억제·PostgreSQL 동시성 · HEAVY · 구현: Opus 실험군 R1·R3, Kimi R2·R4~R7 · 검수: Sol medium.
- 라운드: 본선 R1부터 R7까지 7라운드, dev-release 통합 수렴 3라운드, 운영 문서 2라운드. 첫 검수 합격률 0%(R1 불합격), 본선 R7 Sol 독립 검수 PASS 뒤 통합에서 lease 중첩과 PID 재사용 취소 경쟁을 닫고 문서 R2 LIGHT 검수까지 치명0·중요0·사소0 PASS. 첫 편성 시각 2026-07-27 15:21 KST부터 본선 합격 2026-07-28 03:23 KST까지 약 12시간 2분이며, 통합·문서 수렴은 이후 원장 이벤트로 별도 추적한다.
- 모델 비교: Opus 실험군은 R1에서 PostgreSQL 공유 카운터의 기본 구조를 만들었지만 첫 검수에서 중요 9건으로 불합격했고, R3 뒤 재검수도 중요 6건으로 불합격했다. Kimi는 R2와 R4~R7에서 검수 발견을 단계적으로 닫았으며 최종 합격까지 다섯 수정 라운드가 필요했다. 이 한 랠리만으로 모델 우열을 일반화하지 않는다.
- 발견 수렴: 실제 TypeORM 저장소 생성자 500 → migration TRUNCATE/스키마 우회 → 활성 키 보호·XFF 신뢰 경계 → 서버 전체 원자 claim/dedupe → 키 회전 lease/fence → 느린 정상 SQL을 자르는 statement timeout → TTL과 timeout 분리·QA 서버 실패 정리로 수렴.
- 결말: 체크포인트 `906a44aef15eb1f7ac5e0127f54ac61239fc1836` (`fix(open-api): 분산 사용량 제한 안정화 (#79)`), 43파일. focused 341/341, 전체 585/585, detectOpenHandles·tsc·diff 0, migration 4쌍, 격리 PostgreSQL 15.15 PASS. 작업 일지 `docs/issue-79-distributed-rate-limit-report.md`는 커밋에서 제외했다.
- 관찰: (1) 프로세스 메모리 제한은 PM2 다중 작업자에서 전역 계약이 아니다. PostgreSQL 원자 갱신과 실제 다중 연결 시험이 필요하다. (2) 짧은 TTL에서 계산한 statement timeout은 합법적인 느린 SQL도 계속 rollback시킬 수 있으므로 별도 설정과 fail-fast 경계가 필요하다. (3) 하네스는 누적 행 수보다 시나리오 전후 증가량을 비교해야 이전 정상 행을 실패로 오판하지 않는다. (4) assertion 실패 경로에서도 QA 소유 서버만 닫히는지 열린 핸들로 확인해야 한다.

### 2026-07-28 [판:openapi-fix] 랠리 #77 — 키 발급 응답 로그 비밀값 제거

- 성격: 응답 로그 보안·JSON 직렬화 의미 보존·실제 dev 키 수명주기 · HEAVY · 구현: Kimi · 검수: Sol medium.
- 라운드: 5라운드. 첫 검수는 Date·Buffer·toJSON 의미 변형으로 불합격했고, 문자열 비밀값만 serialization 경계에서 가리는 replacer와 실제 POST→interceptor→로그 시험으로 수렴했다.
- 결말: 체크포인트 `db538abad5250625488c47bfc4a44220ede884ec`, PR #83을 거쳐 dev 반영·실제 키 발급 로그 QA·폐기 후 401까지 PASS. 이슈 #77 close 완료.
- 관찰: 보안 redactor는 객체를 재귀 복사하기보다 JSON.stringify replacer에서 primitive string만 가려 Date·Buffer·toJSON·undefined·BigInt 의미를 보존해야 한다.

### 2026-07-28 [판:openapi-fix] 랠리 #78 — 가드 단계 429 사용량 기록

- 성격: 분당·일일 429 기록·창별 중복 억제·비동기 저장 상한 · HEAVY · 구현: Kimi · 검수: Sol medium.
- 라운드: 3라운드. 첫 검수 뒤 창별 dedupe, in-flight 100 상한, settle 추적과 결정적 Promise 시험을 보완해 최종 PASS.
- 결말: 체크포인트 `8eae3c684c6e0c3f2ffc2f938320107889e4372e`, PR #84 dev 반영. 실제 dev에서 분당·일일 429가 창당 각 1건 기록되고 정상·400 기록과 분리됨을 확인해 이슈 #78 close 완료.
- 관찰: best-effort 저장도 settle 가능성과 메모리 상한을 함께 가져야 하며, 고정 Promise tick 시험 대신 완료 체인을 직접 제어해야 한다.

### 2026-07-28 [판:openapi-fix] 랠리 #81 — 검색 page 상한

- 성격: HTTP pagination 계약·거대 OFFSET 차단·고객 가이드 동기화 · HEAVY/LIGHT · 구현: GLM·Kimi·Opus · 검수: Sol medium.
- 라운드: 5라운드와 post-rebase 확인. page=1000 허용, 1001·MAX_SAFE_INTEGER 400, 실제 service와 repository builder skip 경계를 직접 시험하고 recorder의 결정적 비동기 시험까지 수렴했다.
- 결말: 체크포인트 `d10423b6562ebe065b7d10a36d41f275759a7bd2`, PR #84 dev 반영. 실제 HTTP page 1000=200, 초과값=400과 고객 가이드 4절 동기화를 확인해 이슈 #81 close 완료. 고객 전달 PDF 재생성은 외부 감독 담당.
- 관찰: DTO decorator만으로는 직접 service 호출을 막지 못하므로 normalization 경계에서도 400을 강제하고 실제 query builder의 skip 값을 확인해야 한다.

### 2026-07-28 [판:openapi-prod-prep] 운영 배포 준비·실행·실측 QA

- 성격: dev PM2 다중 작업자 재측정, 운영 환경 변수·마이그레이션 준비와 승인 후 실행, release·실배포·운영 QA · HEAVY · 지휘: gpt-5.6-sol 프로젝트 감독.
- 라운드: 운영 절차서 작성·검수 R1부터 R8까지 8라운드, dev PM2 실행 1라운드와 독립 검수, 운영 A부터 D까지 4단계와 최종 독립 검수. 운영 QA는 3차에서 최종 PASS했다.
- 모델: 실행 Kimi K3 1M low, 검수 Sol medium, 중계 Luna low. 최종 독립 검수는 미등록 opencode에서 GLM 5.2 max를 사용했으며 결과 자체는 증거 기반 PASS로 유지하되 편성 비준수로 기록했다.
- 결과: dev PM2 임시 다중 작업자에서 동시 15건이 정확히 200 10건·429 5건이었고 원래 1개로 복구했다. 운영에는 96자 CSPRNG 서명 비밀을 원문 비기록으로 주입하고 migration 5개를 순서대로 적용했다. PR #85·#86을 일반 머지하고 main `053cd1e6f258b0ff9a252f7e83aea8e1d8568296`을 배포했다. 운영 PM2 2/2 online, 로컬·공개 health 200, 최종 QA 200 10건·429 5건, 두 작업자 CPU 증가, 로그 평문 0건, 폐기 후 401, 활성 QA 세션 0건을 확인했다.
- 전환 이벤트: 인터넷 단절 뒤 전 작업자·중계기·companion 생존을 점검해 재개했다. 운영 QA 1차는 9/6, 2차는 작업자 분산 증거 부족, 3차는 정확한 10/5와 두 작업자 사용 증거로 수렴했다. `DISPATCH_FAILED` 2회는 터미널 이상이 아니라 카드가 `pending`이었던 것이 원인이었다. 복구 국면에도 라우터와 roster만 쓰도록 mechanics 규칙을 보강했다.
- 결말: 치명 0·중요 0·사소 1 PASS. 최종 증거는 `/tmp/orca-evidence/openapi-prod-prep/final-review/report.md`. routing events는 `.orca/routing-events/openapi-prod-prep.jsonl`에 남았고, 자동 선택 기록 누락과 미등록 opencode 편성은 비준수로 별도 보고했다. 판 종료 때 전용 워크트리·브랜치·터미널·자식 프로세스를 정리했다.

### 2026-08-04 [판:upstream-sync-1] upstream 전체 동기화·운영 앱 교체·roster rebind 첫 실전

- 성격: upstream 대규모 병합, 충돌 13건, 전체 시험 실패 분류, macOS 로컬 빌드·실기동 E2E, 운영 앱 교체, role-roster 수명주기 · HEAVY · 지휘: gpt-5.6-sol 프로젝트 감독.
- 본선 결과: upstream/main `a6b14eb04`을 bootstrap에 병합해 충돌 13건을 해소했고, 최종 체크포인트 계보는 운영 앱 교체 빌드 `4cf749aaab07`까지 이어졌다. 시험 실패는 10범주, 35 test + unhandled 1로 분류했다. Node 24, macOS Bash 3.2, ad-hoc 서명/TCC, ambient `GIT_CONFIG_COUNT`를 다음 랠리의 고정 환경 관문으로 남겼다.
- 운영 교체: 구 PID 43323에서 신 PID 62007로 교체했고 appVersion `1.4.168-rc.1.local.1785831912638.4cf749aaab07`, runtime ready, userData 불변을 확인했다. 교체 스크립트의 `RESULT: FAIL`은 60초 대기 부족으로 생긴 오판이었으며 후속 실측으로 PASS 정정했다.
- roster 첫 실전: 새 공식 동사 `roster rebind`로 project-supervisor `roster_b93ae3c47e7b`와 relay `roster_e2c3e64c4e24`를 새 pane에 옮기고 receipt가 아니라 `list/show/resolve` 장부로 검증했다. `terminal create --role` 성공 receipt와 실제 등록 결과가 어긋나는 결함 A를 재현했고, Kimi K3 1M max 구현 → Sol medium 독립 검수 1라운드 PASS로 `f5de48c11`을 만들었다.
- 감시 복구: relay를 Luna high `orca-lean`으로 복구하고 실제 순찰 로그 append와 `RELAY_SUCCESSOR_READY`를 확인했다. 옛 kicker PID 69328은 정확 PID만 종료하고 새 PID 23542, PPID 1로 재기동했다. companion은 여러 실패를 겪은 뒤 launchd PID 63293, PPID 1로 복구했으며 보호 대상 전임 감독 PID 2927은 건드리지 않았다.
- 플레이북 랠리: GLM medium 문서 작업 → Sol medium 검수. R1은 정책 충돌 등 critical 1·major 4·minor 1 FAIL, R2는 월간 병합 원본과 방향 개수 major 1·minor 1 FAIL, R3는 critical·major·minor 0 PASS로 수렴했다. 체크포인트 `4d7f26948`은 `docs/upstream-sync-playbook.md`를 처음 Git 추적하고 maintenance 양방향 링크를 함께 넣었다.
- 사고와 교훈: 미추적 살아있는 플레이북을 작업자가 전면 교체하다 삭제해 Git 복구가 불가능했고, 셸 전체 쓰기로 복원했다. 살아있는 플레이북은 생성 직후 Git 추적·커밋한다. 독립 검수자가 `git write-tree`를 읽기 전용 확인에 사용한 일과 FAIL 본문에 `outcome=succeeded`를 보낸 lifecycle 불일치도 있었으므로, 검수 spec에는 객체 생성 금지와 본문 판정·outcome 일치 조건을 명시한다. worker의 긴 전체 파일 재작성보다 좁은 patch를 강제한다.
- 결말: 결함 A 소스 체크포인트 `f5de48c11`, 판 마감 문서 체크포인트 `4d7f26948`. Computer Use, terminal close receipt, 버전 표시, 세션 GC는 ready로 보존하고 이번 판에서 발령하지 않았다.

### 2026-08-05 [판:improvement-1] 개선 판 1회차 — A-I 트랙 통합·운영 앱 교체

- 성격: 모델·검수·복구·교체가 결합된 오케스트레이션·macOS 서명/TCC·동시성·수명주기·통합 운영 · 무게: HEAVY
- 라운드: 장부 result에서 확인된 트랙별 단계는 A R1→R7, B R1→R3, C R1, D R1→R3, E R1→R3, F 조사 1건, G R1→R3, H R1→R2, I R1이며, 통합 마감은 closeout R1→R6·교차검수 R1→R3·서명 빌드·격리 E2E·운영 교체로 이어졌다. 구현 모델-effort·검수 모델-강도/범위·치명·중요·사소 누계와 전체 총 라운드 수는 result에서 확인되지 않아 미상으로 둔다.
- 전환 이벤트: 최종 통합 commit `165153a06`의 서명 빌드·격리 패키지 E2E PASS 뒤 운영 앱을 PID `62007`→`30017`으로 교체했다. 교체 뒤 supervisor/relay rebind 및 worker_done capability 재검증이 필요했고, 폐기된 capability에 대한 worker_done이 6회 거부된 뒤 감독이 수동 종결했다. relay v2·companion·kicker는 PPID 1로 복구했다.
- 결말: 마감 완료 — receipt 실효 PASS와 TCC 권한 유지 PASS를 확인했다. `get-app-state`는 구 빌드와 동일한 결함 E로 후속 이월한다.
- 관찰: 고정 서명은 TCC grant 유지 대상을 충족했지만 권한 표시와 실제 기능 동작은 분리해 기록해야 한다. 앱 교체 뒤에는 dispatch capability 폐기와 rebind를 복구 절차의 한 단계로 고정하고, 재검증 실패 시 worker_done을 성공으로 올리지 말고 감독 수동 종결까지 남겨야 한다.

### 2026-08-07~08 [판:orca-integration-1] 영수증 강제 변경 통합·실앱 재검증

- 성격: 보안 경계·오래된 브랜치 통합·실앱 E2E·문서 생성물 동기화 · 무게: HEAVY · 구현: GLM 5.2 max · 검수: Sol medium.
- 라운드: 통합 구현 뒤 독립 검수 R1에서 중요 2건(DB 인덱스 복구 호출 유실, 잘못된 receipt 안내 7곳) → R2 수정 뒤 독립 재검수 중요 1건(번들 안내서 stale) → 최종 R3에서 생성물 동기화 후 좁은 독립 재검수 `CODE_PASS`. 실앱 4시나리오와 변이 거부는 R1 통과 증거를 재사용했다.
- 전환 이벤트: R3 범위를 `src/cli/bundled-skill-guides.ts`의 결정적 재생성 한 건으로 축소해 전체 실앱 검증 반복을 막았다. DeepSeek 대화형 중계기 교체는 승인 창 때문에 두 번 실패해 중단하고 Luna로 복귀했다.
- 결말: 합격·머지·push 완료. 복구용 카드 커밋 `15e747676063ceb57596811d8d901c40941e46d3`, 병합 커밋 `538750de6191f83d20c2f24499bb71e3a73c8b93` (총 3왕복).
- 관찰: 대화형 Command Code 창은 무인 셸 순찰과 권한 전제가 맞지 않는다. DeepSeek 자체 실패로 기록하지 말고, 저비용 중계기는 헤드리스 1회 호출 구조로 따로 검증한다. 중계기 교체는 후임의 실제 로그를 본 뒤 선임을 닫는 순서를 지켜 감시 공백을 막았다.

### 2026-08-10 [판:conductor-core-contract-1] A3-F5 — 상주 보조 이름 타입·상태 방어

- 성격: 상주 신분 교대 안전 계약·입력 타입·변형 방어 · HEAVY · 구현: GLM 5.2 max · 검수: Sol medium.
- 라운드: EXP-RI-1에서 문맥 독립 A가 중요 결함 1개, 문맥 공유 B가 0개, 다른 모델 심판이 중요 결함 2개를 찾은 뒤 A3-F5 1라운드로 두 결함을 수정했다. A3-R5 독립 재검수에서 치명 0·중요 0·경미 0 `CODE_PASS`.
- 검증: 비문자 이름 타입 공격 12/12 거부, 상태 공격 6/6 거부, 저장소 밖 복사본 변형 4/4 거부, 전체 149 passed·520 subtests. 검수 스냅샷 `6f96389048b7a7da773b1d50588b7d46738a20c5`의 추적 변경은 원래 작업트리 diff와 SHA-256이 같았다.
- 결말: 체크포인트 `c3d406c8e8a8a573f7d683acb24841e31f6778a4`, 변경 2파일. push·merge·배포·워크트리 정리는 하지 않았다.
- 관찰: 같은 모델 자기 검수 한 표본에서 0개, 새 세션 독립 검수에서 1개, 다른 모델 심판에서 2개가 나왔다. 한 표본으로 원인을 확정하지 않되 독립 검수를 없앨 근거는 없고 유지할 근거가 생겼다. 새 워크트리 검수에 작업자 커밋을 강요하지 않고 `git stash create` 익명 스냅샷을 사용하면 원래 작업트리를 바꾸지 않은 채 정확한 추적 변경을 고정할 수 있다.

### 2026-08-10 [판:conductor-core-contract-1] A11-F2 — 모름 오분류·host run 우회 방어

- 성격: 상태 판정·host 주소 계약·변형 방어 · HEAVY · 구현: GLM 5.2 max · 검수: Sol xhigh.
- 복구: 옛 작업자 사망 뒤 미커밋 5파일을 보존했다. `/tmp`의 A11-R1 상세 보고서는 재부팅 뒤 사라졌으므로 읽었다고 꾸미지 않고 장부 메시지 `msg_350a2466b249`, 원래 dispatch TASK, 현재 코드로 증거를 다시 만들었다.
- 검증: 알려진 False를 None으로 바꾸는 변형 3/3, `--run` 선택화·board 대체·고정 문자열 대체 3/3, 약한 빈 값·상태 추가 변형을 모두 거부했다. unittest 131/131, pytest 131/131·84 subtests. 검수 스냅샷 `33831ff499299322a0726da6057ce0bb4dd3f4ff`은 원래 작업트리 diff와 SHA-256이 같았다.
- 결말: A11-R2 치명 0·중요 0·경미 0 `CODE_PASS`, 체크포인트 `7268fc52e0f796c1055fd4a42e392f68766df9c8`, 변경 5파일. push·merge·배포·워크트리 정리는 하지 않았다.
