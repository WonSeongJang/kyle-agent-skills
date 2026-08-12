# 디자인 스킬 설치 전 안전 검토

## Why

[kyle]의 디자인 스킬이 프로젝트 파일, 비밀값, 외부 서비스에 예상 밖의 동작을 하지 않도록 고정 커밋의 동봉 파일을 먼저 전수 확인한다.

## 판정 기준

- 고정 커밋 tarball을 메모리에서 열어 설치 대상 파일을 모두 읽었다.
- 텍스트 파일은 파괴 명령, 자식 프로세스, 파일 쓰기, 환경 변수·비밀값, 네트워크, 프롬프트 인젝션 흔적을 전수 검색했다.
- 실행 스크립트는 외부 전송, 쓰기 범위, 자식 프로세스와 삭제 범위를 코드 문맥으로 다시 확인했다.
- 바이너리는 파일 서명과 내부 구조를 확인했다.
- 설치만으로 자동 실행되는 코드와 사용자가 명령을 골라야 실행되는 코드를 구분했다.

## 후보별 결과

| 후보 | 고정 커밋 | 읽은 범위 | 안전 판정 | 근거 |
|---|---|---:|---|---|
| Impeccable | `ae388ac58fb33aade50fc47e2be07c3192dcaabd` | 154개 텍스트, 3,226,865바이트 | **보류** | 필수 `context.mjs`가 기본값으로 `impeccable.style/api/version`을 조회하고 홈 폴더 `~/.impeccable/update-check.json`에 쓴다. `concept-seed.mjs`는 외부 `/api/roll` 조회와 선택 결과 `/api/chosen` POST 텔레메트리를 기본 제공한다. 편집 후크, 로컬 서버, 소스 삽입·수정, 임시 파일 재귀 정리까지 포함해 전역 설치 전에 별도 비전송 기본값 또는 로컬 안전 패치 결정이 필요하다. |
| Effective HTML 6종 | `d95debbaef15af1d201fc6c10c77cf92b524a0d6` | 18개 텍스트, 49,313바이트 | 설치 | 실행 스크립트·비밀 접근·파괴 명령 없음. 외부 문서 링크 2개만 있으며 6개 스킬은 로컬 단일 HTML 산출 지침이다. |
| Taste Skill | `e988add20dab0fa97d7a76781c48961c8184288e` | 2개 텍스트, 88,318바이트 | 설치 | 실행 스크립트 없음. Picsum, Simple Icons, 디자인 시스템 문서 같은 외부 자산·참고 URL은 있으나 자동 전송은 없다. |
| Emil Design Eng | `78761e1b57f97dce65b983d640c70a68f39e8163` | 2개 텍스트, 28,296바이트 | 설치 | 실행 스크립트·파일 쓰기·비밀 접근 없음. 학습 자료 링크 2개만 있다. |
| Apple Design | `78761e1b57f97dce65b983d640c70a68f39e8163` | 2개 텍스트, 23,785바이트 | 설치 | 순수 지시형. 네트워크·쓰기·비밀 접근·파괴 명령 없음. |
| Extract Design System | `1873741ba8dea755e35e6e15134f7918cd58e036` | 4개 텍스트, 4,250바이트 | 설치 | 공개 사이트를 브라우저로 읽어 로컬 Markdown·JSON 결과를 만드는 지시형 스킬. 자동 스크립트와 비밀 접근 없음. |
| Canvas Design | `f17010c9bb483898c1d9c9f42dde2b3a98889434` | 83개, 5,554,003바이트 | 설치 | 실행 스크립트 없음. 54개 TTF/OTF의 서명, 테이블 수, 오프셋 범위를 모두 검사해 54/54 정상. 나머지는 SKILL, Apache-2.0, 폰트 OFL 문서다. |
| Frontend Design | `f17010c9bb483898c1d9c9f42dde2b3a98889434` | 2개 텍스트, 18,434바이트 | 설치 | 순수 지시형. 실행·쓰기·비밀 접근 없음. |
| Web Design Reviewer | `0a6e37e4e242c944380228fa29dbd14e64ac1b63` | 4개 텍스트, 25,142바이트 | 설치 | Playwright를 사용해 화면을 읽고 수정안을 내는 지시형. 자동 설치·비밀 접근·파괴 명령 없음. 소스 수정은 사용자가 검수 후 선택하는 범위다. |
| Anti UI Slop | `0a6e37e4e242c944380228fa29dbd14e64ac1b63` | 2개 텍스트, 6,694바이트 | 설치 | 명시적으로 지시형이며 UIZZE 공개 카탈로그 조회만 요구한다. 인증 정보·실행 코드·자동 전송 없음. |
| Slides Grab 7종 | `745c931c8f5556d8b9fdfe6718c8a507f6223935` | 스킬 22개 파일 + 실행 관련 103개 파일, 1,566,608바이트 | 설치, 제한 실행 | npm `slides-grab@1.5.0`의 `gitHead`와 일치한다. 내보내기·편집기·이미지 생성 명령은 자식 프로세스, 로컬 파일 쓰기, 선택적 API 키를 사용하지만 설치만으로 실행되지 않는다. 평가는 HTML·로컬 내보내기만 사용하고 이미지 공급자, `yt-dlp`, Codex/Claude 편집 하위 프로세스는 호출하지 않는다. |

## 보류 항목 상세

### Impeccable

- 출처: https://github.com/pbakaus/impeccable
- 설치하지 않은 이유:
  - `scripts/context.mjs`는 24시간마다 업데이트 확인을 하고 홈 폴더 캐시를 쓴다.
  - `scripts/concept-seed.mjs`는 외부 롤 API를 쓰고 선택 결과 텔레메트리 POST 경로를 제공한다.
  - `IMPECCABLE_NO_TELEMETRY=1`, `DO_NOT_TRACK`, `IMPECCABLE_NO_UPDATE_CHECK=1`로 일부를 끌 수 있지만 스킬 문서의 기본 실행 명령에는 이 보호가 강제되지 않는다.
  - 훅·라이브 편집 경로가 프로젝트 소스를 수정하고 임시 세션을 재귀 정리하므로 전역 링크 전에 비전송 기본값을 정해야 한다.
- 재검토 조건: 고정 커밋을 그대로 유지하면서 텔레메트리·업데이트 확인이 기본 비활성인 상류 버전이 나오거나, 로컬 안전 래퍼를 정본 정책으로 채택할 때.

## 설치 출처

- https://github.com/plannotator/effective-html
- https://github.com/leonxlnx/taste-skill
- https://github.com/emilkowalski/skills
- https://github.com/arvindrk/extract-design-system
- https://github.com/anthropics/skills
- https://github.com/github/awesome-copilot
- https://github.com/NomaDamas/slides-grab
