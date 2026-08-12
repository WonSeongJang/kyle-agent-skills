Merge these blocks into `~/.claude/CLAUDE.md` if equivalent policies are missing. If similar blocks already exist, edit the existing text instead of pasting duplicate copies.

```md
## API 시크릿 / 프록시 원칙

- 외부 API 비밀 키는 공개용 env(`VITE_*`, `NEXT_PUBLIC_*`, `REACT_APP_*`, `NUXT_PUBLIC_*`, `EXPO_PUBLIC_*`, `PUBLIC_*`)에 넣지 않는다.
- 초기 PoC 단계에서는 로컬에서만 direct env 예외를 잠깐 허용할 수 있다.
- 운영 전환 단계에 들어가면 개발/운영 모두 `/api/...` 프록시 구조로 통일한다.
- 비밀 키는 코드에 직접 남기지 않는다.

## 파일/디렉토리 삭제 안전 프로토콜

파일이나 디렉토리를 삭제할 때는 **즉시 삭제(rm) 금지**. 반드시 아래 루프를 따른다.

1. **이동**: 삭제 대상을 `~/.trash-staging/` 하위로 이동 (mv). 프로젝트명+날짜로 구분.
   - 예: `~/.trash-staging/mompick_2026-02-11/`
   - 원본 경로를 유지하여 이동 (구조 파악 가능하도록)
2. **보고**: kyle에게 이동 완료 목록을 보여주고, 실제 삭제 승인을 요청
3. **대기**: kyle이 검수 후 삭제 승인할 때까지 절대 `rm` 하지 않음
4. **삭제**: kyle 승인 후에만 `rm -rf ~/.trash-staging/{해당 폴더}` 실행

예외:
- 빌드 산출물, node_modules, __pycache__ 등 재생성 가능한 파일은 즉시 삭제 허용
- git에서 복구 가능한 단일 파일도 kyle 확인 없이 삭제 금지 (git 히스토리가 있어도 실수 방지)

## 에이전트 경로 정책

- 전역 지침은 `~/.claude/CLAUDE.md` 를 원본으로 두고, Codex는 `~/.codex/AGENTS.md`, GJC는 `~/.gjc/agent/AGENTS.md`에서 그 원본을 바라보는 심볼릭 링크를 사용한다.
- agent 역할 프롬프트는 도구별 로컬 디렉토리로 관리할 수 있다.
- Codex에서는 `~/.codex/agents/`를 우선 사용한다.
- Claude에서는 `~/.claude/agents/`를 우선 사용한다.
- 해당 도구 쪽 역할 파일이 없으면 반대쪽 경로를 fallback으로 확인한다.
- 역할 파일명은 가능하면 양쪽에서 동일하게 유지한다.
- Codex 모델 라우팅은 `~/.codex/agents/` 쪽 별도 문서/설정에서 관리한다.
- agent 디렉토리는 스킬처럼 자동 symlink 공유 대상으로 취급하지 않는다.

## 스킬 경로 정책 (선택 적용)

기본 원칙:
- 기존 스킬 구조는 건드리지 않는다.
- **명시적으로 지정한 스킬만** Claude 원본 + Codex·GJC 링크 방식으로 운영한다.
- 기존에 이미 내장되어 있거나 별도 요청 없이 그냥 존재하는 스킬까지 자동으로 동기화하지 않는다.
- 전역 지침의 Codex 쪽 호환 링크의 기준 표기는 `~/.codex/AGENTS.md` 로 둔다.
- macOS 기본 파일시스템처럼 대소문자 비구분 환경에서는 `~/.codex/AGENTS.md` 와 `~/.codex/agents.md` 가 실제로 같은 파일일 수 있으니, 이를 서로 다른 2개 파일로 오해하지 않는다.

스킬 설치/생성 요청 기본값:
- Kyle이 어떤 스킬의 **신규 설치 또는 신규 생성**을 요청하면, 그 요청 자체를 해당 스킬에 대한 적용 승인으로 간주한다.
- 처리 순서는 기본적으로 아래를 따른다:
  1. 먼저 `~/.claude/skills/{skill-name}` 쪽에 스킬 원본을 설치하거나 만든다.
  2. `~/.codex/skills/{skill-name}` 와 `~/.gjc/skills/{skill-name}` 에는 복사본을 두지 말고, 위 Claude 원본 경로를 바라보는 심볼릭 링크를 만든다.
  3. 이후 수정은 가능한 한 원본 한 곳만 고쳐서 Claude, Codex, GJC가 같은 스킬 파일/디렉토리를 함께 쓰게 한다.
- 이미 도구별 경로에 따로 스킬이 있으면, 내용 보존을 먼저 확인한 뒤 Claude 쪽을 원본으로 정리하고 Codex·GJC는 그 원본을 바라보게 맞춘다.
- GJC 사용자 스킬 링크를 검색하려면 `gjc config set skills.enabled true`와 `gjc config set skills.enablePiUser true`를 적용한다.
- 충돌 위험이나 어느 쪽을 원본으로 삼아야 할지 불분명하면, 작업 전에 Kyle에게 확인한다.

현재 지정 스킬:
- 이 목록에는 Kyle이 공유 대상으로 **직접 지정했거나**, 신규 설치/생성을 **직접 요청한** 스킬만 기록한다.
- `<skill-name>`
  - 원본: `~/.claude/skills/<skill-name>`
  - 링크: `~/.codex/skills/<skill-name>`, `~/.gjc/skills/<skill-name>` → `~/.claude/skills/<skill-name>`

확장 규칙:
- 다른 스킬까지 같은 구조로 바꾸기 전에는 반드시 Kyle 확인을 먼저 받는다.
- 단, Kyle이 특정 스킬의 **신규 설치 또는 신규 생성**을 직접 요청한 경우에는 위 기본값에 따라 바로 Claude 원본 + Codex·GJC 링크 방식으로 처리한다.
- 기존 내장 스킬이나 예전부터 있던 스킬은 Kyle이 별도로 지정하지 않으면 이 규칙으로 자동 전환하지 않는다.
- 대소문자 비구분 환경에서는 `~/.codex/agents.md` 를 별도 중복 파일이라고 가정하고 단독 삭제하려 들지 않는다. 먼저 같은 inode 인지 확인한다.
```
