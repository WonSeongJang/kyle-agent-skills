---
name: repo-rules-bootstrap
description: Kyle의 공통 작업 원칙(개발 규칙·사고 사례 누적·Git 안전·시점별 문서 규칙)과 문서 구조(TODO, phase-history, daily, glossary, AGENTS.md 심볼릭 링크)를 임의의 개발 레포에 설치하거나 점검하는 스킬. "공통 규칙 세팅해줘", "이 레포에도 작업 원칙 깔아줘", "CLAUDE.md 규칙 복붙", "문서 구조 부트스트랩", "데일리/투두/페이즈히스토리 만들어줘" 요청 시 사용. 멀티에이전트 오케스트레이터까지 필요하면 workflow-bootstrap 스킬을 쓴다.
---

# Repo Rules Bootstrap

## Why

Kyle의 개발 레포마다 같은 공통 작업 원칙과 문서 구조(시점별 4문서)를 손으로 복붙하면 레포마다 조금씩 어긋난 사본이 생긴다. 이 스킬은 템플릿 원본 한 곳(`assets/common-work-rules.md`)에서 설치하고, 이미 있는 레포는 깨뜨리지 않고 빈 곳만 채운다.

## 적용 범위 (중요)

- **대상**: [kyle] 자체 관리 레포 (신규 프로젝트, inquiry-service류).
- **금지**: 모두의인증 외주 4개 레포(`modoo-auth-backend`, `moducerti-customer-web`, `moducerti-partners-web`, `moducerti-admin-web`) — 그 레포들은 CLAUDE.md 없이 `moducerti-*` 스킬이 규칙 역할을 하기로 정리됨. 여기 설치하면 이중 기준이 된다.
- 허브(모노 워크스페이스)의 하위 레포에 설치할 때는 상위 허브 CLAUDE.md와 충돌하는 규칙이 없는지 먼저 비교한다.

## 절차

### 1. 현황 점검 (읽기 전용)

```bash
pwd && git rev-parse --show-toplevel
ls -ld CLAUDE.md AGENTS.md docs docs/TODO.md docs/phase-history.md docs/daily docs/glossary.md 2>/dev/null
git branch --show-current
```

점검표를 만들어 보고한다: 각 항목 `있음 / 없음 / 형식 다름`.
`AGENTS.md`는 심볼릭 링크인지 실파일인지 구분한다 (`ls -l`, macOS 대소문자 비구분 주의 — `AGENTS.md`와 `agents.md`가 같은 파일일 수 있음, inode 확인).

### 2. 문서 구조 생성 (없는 것만)

- `docs/` , `docs/daily/` 디렉토리
- `docs/TODO.md` — 헤더만: `# <레포명> 후속 작업 큐` + "활성 작업만 둔다. 완료되면 지우고 phase-history에 기록" 한 줄
- `docs/phase-history.md` — `assets/phase-history-template.md` 복사
- `docs/glossary.md` — 헤더만: `# 용어사전` + "새 용어는 사용 전에 여기 먼저 정의" 한 줄
- 이미 있는 파일은 절대 덮어쓰지 않는다. `docs/architecture/phase-history.md`처럼 옛 위치에 있으면 `git mv`로 `docs/phase-history.md`로 이동하고 참조를 갱신한다 (이동 전 [kyle] 확인).

### 3. CLAUDE.md 병합

- **없으면**: `assets/common-work-rules.md`의 본문(구분선 아래)을 그대로 새 `CLAUDE.md`로 생성하되, 최상단에 레포 한 줄 소개(`# <레포명>` + Why 한 문장)를 추가한다.
- **있으면**: 통째 교체 금지. 템플릿의 섹션 단위(`공통 작업 원칙`의 소절들, `잠긴 계약`)로 비교해서 **없는 소절만** 추가한다. 이미 비슷한 소절이 있으면 내용을 나란히 보여주고 [kyle]에게 병합 방향을 확인한다.
- 사고 사례·잠긴 계약 소절은 빈 틀로 설치한다 — 다른 레포의 사례를 복사하지 않는다 (사례는 레포 소속).

### 4. AGENTS.md 심볼릭 링크

- `AGENTS.md`가 없으면: `ln -s CLAUDE.md AGENTS.md`
- 실파일로 존재하면: 내용을 CLAUDE.md와 비교해 병합 여부를 [kyle]에게 확인한 뒤에만 링크로 전환 (원본은 `.staging/`으로 이동, 삭제 금지)

### 5. 검증과 보고

- `ls -l AGENTS.md` 링크 확인, 생성 파일 목록 확인
- 보고 형식: `생성함 / 이미 있었음 / [kyle] 판단 필요` 3분류
- 대상 레포가 git이면 변경을 커밋한다 (push는 [kyle] 승인 후)

## 원칙

- **멱등**: 두 번 실행해도 안전. 있는 것은 건드리지 않는다.
- **파괴 금지**: 덮어쓰기·삭제 없음. 대체가 필요하면 `.staging/` 이동 + [kyle] 확인.
- 템플릿을 고치고 싶으면 이 스킬의 `assets/common-work-rules.md` 원본을 고친다 — 레포별 사본을 고치면 다시 어긋난다. 단, 사고 사례와 잠긴 계약의 **내용**은 각 레포 소유다.
- 절대경로 하드코딩을 대상 레포에 남기지 않는다.

## 관련

- 멀티에이전트 오케스트레이터(`workflow/` 엔진)까지 설치하려면 `workflow-bootstrap` 스킬.
- 이 구조의 배경 문서: Obsidian `바이브코딩/가이드북/TODO 작업 큐 운영 가이드북.md`.
