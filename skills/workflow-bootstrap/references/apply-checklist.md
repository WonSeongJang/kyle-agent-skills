# 적용 체크리스트

## 설치 전

- git 저장소인지 확인
- 현재 branch 확인
- `workflow/` 기존 존재 여부 확인
- `docs/` / `docs/daily/` 존재 여부 확인
- `AGENTS.md` / `CLAUDE.md` 존재 여부 확인

## 설치 중

- `workflow/` 코어 파일 배치
- `workflow/tasks/` 생성
- `workflow.yml` 기본값 생성 또는 갱신
- `docs/daily/` 없으면 생성
- 오늘 날짜 디렉토리 생성
- tool 로그 파일 기본 헤더 생성
- 공통 `CLAUDE.md` 운영 블록 병합

## 설치 후

- `python workflow/orchestrator.py config` 또는 동등 명령이 동작하는지 확인
- `workflow.yml` override 값이 최소인지 확인
- 코어 파일에 프로젝트 고정 절대경로가 없는지 확인
- `workflow/tasks/`에 runtime 샘플 파일이 섞여 있지 않은지 확인
- `CLAUDE.md`에 프로젝트 전용 규칙과 공통 운영 규칙이 섞여 있더라도 최소한 구조가 구분되어 있는지 확인
