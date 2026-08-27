# 후보와 보류 항목

새 디자인 스킬을 설치하거나 로스터 상태를 바꿀 때만 읽는다.

## 보류

| 후보 | 이유 | 다시 검토할 조건 |
|---|---|---|
| [god-tibo-imagen](https://github.com/NomaDamas/god-tibo-imagen) | 지원되는 공개 API가 아닌 Codex private backend에 의존하고 내장 `imagegen`과 겹침 | 공식 API 또는 안정된 인증 경로가 생기고 내장 도구로 해결할 수 없는 요구가 생김 |
| [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | 큰 스타일 데이터베이스가 현재 로스터와 많이 겹침 | 작은 실제 화면 시험에서 현재 조합보다 분명히 나은 결과를 증명함 |

## 참고만 유지

| 후보 | 이유 |
|---|---|
| [agency-agents](https://github.com/msitarzewski/agency-agents) | 역할과 산출물 구조는 참고할 수 있지만 디자인 전용이 아니고 범위가 큼 |
| [bbarit/terminal](https://github.com/bbarit/terminal) | 디자인 스킬이 아니라 AI 작업 도구에 가까움 |

## 채택 검사표

1. 기존 로스터가 해결하지 못하는 구체적인 빈칸이 있는지 확인한다.
2. README만 보지 말고 실제 `SKILL.md`, 스크립트, 설치 명령을 읽는다.
3. 라이선스와 최근 활동을 확인한다.
4. 쓰는 파일, MCP 설정, 인증 정보, 외부 전송 범위를 확인한다.
5. 제거와 복구 방법을 확인한다.
6. 전역 설치 전에 프로젝트 하나에서 시험한다.
7. 같은 역할의 기존 스킬과 비교해 하나만 기본값으로 둔다.
