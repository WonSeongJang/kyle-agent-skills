---
name: payment-mor-migration
description: 기존 결제 모듈을 Polar/Lemon Squeezy 기반 Merchant of Record(MoR) 구조로 안전하게 전환하는 마이그레이션 스킬. 레거시 결제 코드 분석, 단계적 컷오버, 웹훅 멱등화, 데이터 정합성 검증, 롤백 플랜 수립이 필요한 리팩터링 작업에서 사용한다. 특히 운영 중 서비스에서 무중단 전환/위험 통제가 필요한 상황에 트리거한다.
---

# Payment MoR Migration

## 목표

- 기존 결제 기능을 끊김 없이 MoR 어댑터 구조로 옮긴다.
- 전환 중 데이터 무결성(주문 상태/지급 원장)을 보존한다.
- 문제 발생 시 즉시 롤백할 수 있는 상태를 유지한다.

## 시작 순서

1. `scripts/find_payment_touchpoints.sh`로 결제 관련 코드 범위를 수집한다.
2. `references/mompick-baseline.md`를 읽고 현재 구조의 고정 불변 조건을 확인한다.
3. `references/migration-checklist.md`의 단계별 게이트를 통과하며 전환한다.
4. 정책/수치가 필요한 지점은 `references/source-index.md` 태그를 근거로 기록한다.

## 실전 템플릿 프롬프트

아래 템플릿을 그대로 붙여서 시작하고, `[]`만 현재 상황에 맞게 바꾼다.

### 초급용 1줄 스타터 프롬프트

```text
Use $payment-mor-migration to 계획해줘: payapp/payup에서 Polar 또는 Lemon으로 무중단 전환하는 컷오버+롤백 단계만 간단히.
```

```text
Use $payment-mor-migration to 분석해줘: 현재 코드베이스 결제 전환 위험 구간 5개와 우선 대응 순서.
```

```text
Use $payment-mor-migration to 작성해줘: 전환 전후 정합성 SQL 묶음(상태분포, 원장일치, 중복 멱등키, 웹훅 백로그).
```

### 템플릿 1: 운영 서비스 무중단 전환

```text
Use $payment-mor-migration.

상황: 운영 중인 [서비스명] 결제를 [기존 공급자]에서 Polar/Lemon으로 무중단 전환해야 한다.
요구사항:
1) 컷오버 단계를 T-7 ~ T+7 타임라인으로 제시
2) 단계별 게이트(성공률/웹훅오류율/정합성) 정의
3) 즉시 롤백 절차와 롤백 트리거 수치 정의
4) 멱등키 기반 이중 지급 방지 전략 제시
5) source-index 태그로 정책 근거 인용
```

### 템플릿 2: 코드베이스 기반 위험 분석

```text
Use $payment-mor-migration.

현재 저장소에서 결제 전환 위험도를 분석한다.
작업:
1) `scripts/find_payment_touchpoints.sh [repo_path]` 결과 기반 영향 파일 분류
2) 고위험 구간 5개(상태전이/웹훅/원장/환불/재시도) 선정
3) 각 위험 구간의 방어코드/테스트케이스 제시
4) 전환 전 필수 선행수정과 전환 후 정리작업 분리
```

### 템플릿 3: 데이터 정합성 검증 계획

```text
Use $payment-mor-migration.

결제 전환 배포 전후 데이터 정합성 검증 계획을 만든다.
요구사항:
1) 주문 상태 분포 비교 쿼리
2) paid 주문 vs 원장 지급 1:1 일치 검증 쿼리
3) 중복 멱등키 검출 쿼리
4) 웹훅 미처리/오류 백로그 검출 쿼리
5) 실패 시 수동 보정 플레이북(재처리 순서) 제시

출력은 SQL + 운영자가 따라할 실행 순서로 작성한다.
```

## 템플릿 입력 변수 가이드

마이그레이션 템플릿 실행 전에 아래 항목을 먼저 채운다.

| 변수 | 필수 | 설명 | 예시 |
| --- | --- | --- | --- |
| `[서비스명]` | 필수 | 운영 전환 대상 서비스 | `MomPick AI` |
| `[기존 공급자]` | 필수 | 현재 운영 결제사 | `payapp` |
| `[전환 대상]` | 필수 | 신규 결제사 또는 병행 대상 | `polar`, `lemonsqueezy` |
| `[컷오버 윈도우]` | 권장 | 전환 가능 시간대/날짜 | `토요일 02:00~04:00 KST` |
| `[허용 위험도]` | 권장 | 롤백 트리거 임계치 기준 | `성공률 98% 미만 즉시 롤백` |

## 출력 형식 고정 (권장)

템플릿 실행 결과는 아래 순서를 기본으로 한다.

1. 현재 상태 요약: 레거시 구조/의존성/핫스팟
2. 컷오버 계획: T-7 ~ T+7 단계, 각 단계 게이트
3. 롤백 계획: 즉시 조치, 데이터 보호, 재처리 순서
4. SQL 검증 묶음: 상태분포, 원장 일치, 중복 멱등키, 웹훅 백로그
5. 위험 시나리오: 원인·징후·대응을 표 형태로 정리
6. 출처 태그 목록: 사용한 태그 + 원문 링크

## 기본 게이트 임계치 (권장 시작값)

- 결제 성공률: `>= 98%`
- 웹훅 처리 오류율: `< 1%`
- paid 주문 vs 원장 지급 불일치: `0건`
- 중복 멱등키(`payment:*`) 탐지: `0건`
- 컷오버 이후 구 공급자 신규 주문: `0건`

프로젝트 상황에 따라 임계치는 조정하되, 조정 이유를 반드시 기록한다.

## 템플릿 사용 금지사항

- 단계별 게이트 없이 일괄 전환(one-shot cutover) 금지
- 롤백 경로 미준비 상태에서 기본 provider 변경 금지
- 웹훅 멱등 처리 없이 지급 로직 활성화 금지
- SQL 정합성 검증 없이 전환 완료 선언 금지

## 마이그레이션 플레이북

### 1) 범위 동결 (Inventory Freeze)

- 전환 동안 결제 도메인 파일 목록을 고정한다.
- "이번 배포에서 건드릴 파일"을 명시하고 파일 소유권을 분리한다.
- 무관한 리팩터링(네이밍/포맷팅)을 금지한다.

### 2) 표준 도메인 상태 도입

- 내부 상태 모델을 고정한다: `created | pending | paid | failed | refunded | canceled`.
- 레거시 공급자 이벤트/상태를 내부 상태로 매핑한다.
- DB 제약조건(check constraint)과 API 응답 상태를 먼저 맞춘다.

### 3) 어댑터 계층 삽입

- 기존 핸들러 내부에 provider 분기 코드를 직접 넣지 않는다.
- `payment provider -> adapter -> domain service` 형태로 결합을 분리한다.
- 기능 플래그(환경변수)로 새 공급자를 제어한다.

### 4) 웹훅 안전화

- raw body 기반 서명 검증을 공급자별로 분리한다.
- 이벤트 로그 테이블에서 `(provider, event_id)`를 유니크 키로 사용한다.
- 지급/권한 반영은 멱등 키를 사용해 중복 실행을 차단한다.

Polar 마이그레이션 시 추가 주의:

- `event_id`는 가능하면 `webhook-id`를 우선 사용한다. `payload.data.id`를 쓰면 `order.updated/order.paid`가 같은 주문 ID로 충돌할 수 있다.
- Polar 시크릿이 `polar_whs_...` 형태면 raw 문자열로 HMAC 검증해야 한다(base64 decode 금지).
- 서명 헤더 호환성을 위해 `webhook-*`, `x-webhook-*`, `svix-*` 케이스를 모두 처리한다.
- `order_not_found` 같은 영구 불일치는 DB에 에러를 남기되 HTTP 200으로 응답해 재시도 루프를 끊는다.

### 5) 병행 검증 (Shadow Validation)

- 실제 지급 반영 전, 새 경로를 읽기 전용(shadow) 모드로 돌려 결과를 비교한다.
- 기준:
- 주문 상태 일치율
- 결제 금액 일치율
- 지급 크레딧/권한 일치율

### 6) 단계적 컷오버

- 내부 트래픽 비율 또는 대상 상품 단위로 점진 전환한다.
- 전환 단계마다 모니터링/알람을 확인하고 다음 단계로 넘어간다.

### 7) 롤백 준비

- 롤백은 "코드 되돌리기"보다 "경로 전환"이 우선이다.
- 공급자 플래그를 이전값으로 되돌리는 즉시 복구 경로를 항상 보관한다.
- 롤백 시에도 이미 `paid` 처리된 주문은 재차감/재지급하지 않도록 멱등키를 재사용한다.

## 현재 MomPick에 적용할 때 시작점

아래 파일부터 조사한다.

- `api/_lib/payment-provider.ts`
- `api/payments/create-order.ts`
- `api/payments/confirm.ts`
- `api/payments/webhook.ts`
- `src/features/payments/components/*`
- `src/features/payments/services/paymentService.ts`
- `supabase/migrations/*payment*`
- `docs/PAYMENTS.md`

## 출처 추적 규칙

- 결제 정책(수수료/허용 상품/국가/웹훅 동작)은 반드시 태그로 인용한다.
- 태그 사전은 `references/source-index.md`를 단일 기준으로 사용한다.
- 변경 대응 시:
1. `scripts/verify_source_links.sh` 실행
2. 영향 태그 식별
3. 마이그레이션 체크리스트와 구현 코드를 동시 수정

## 리소스

- `references/source-index.md`: 공식 문서 태그 사전
- `references/migration-checklist.md`: 단계별 컷오버/롤백 체크리스트
- `references/mompick-baseline.md`: 현재 코드베이스 기준점
- `scripts/find_payment_touchpoints.sh`: 결제 관련 파일 탐색
- `scripts/verify_source_links.sh`: 출처 링크 점검
