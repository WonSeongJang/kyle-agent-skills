---
name: payment-mor-core
description: Polar와 Lemon Squeezy를 병행 지원하는 Merchant of Record(MoR) 결제 구축 스킬. 신규 프로젝트(제로베이스)에서 결제 어댑터 설계, 체크아웃 생성 API, 웹훅 서명 검증, 멱등 원장 처리, 크레딧/권한 지급, 테스트/운영 체크리스트 구성이 필요할 때 사용한다. 수수료/정산/국가 지원/허용 상품 정책 비교와 공식 문서 출처 추적까지 함께 요구될 때 트리거한다.
---

# Payment MoR Core

## 핵심 원칙

- 결제 흐름은 반드시 `provider-agnostic`(공급자 독립) 도메인 계약 위에 구축한다.
- 성공 리다이렉트 URL은 참고 신호로만 사용하고, 최종 확정은 웹훅/서버 검증으로만 처리한다.
- 웹훅은 반드시 원문 바디(raw body) 기반으로 서명을 검증한다.
- 결제 확정/크레딧 지급은 반드시 멱등 키(idempotency key)로 중복 처리를 막는다.
- 정책성 판단(허용 상품, 국가 지원, 수수료)은 추측하지 않고 `references/source-index.md`의 공식 출처 태그를 근거로 기록한다.

## 시작 순서

1. `references/source-index.md`를 먼저 읽고 태그 체계를 확인한다.
2. `references/polar.md`와 `references/lemonsqueezy.md`를 비교해 이번 요구사항과 맞는 공급자 우선순위를 결정한다.
3. `references/integration-checklist.md` 순서대로 구현한다.
4. 구현 후 `scripts/verify_source_links.sh`로 문서 링크 상태를 점검한다.

## 실전 템플릿 프롬프트

아래 템플릿을 그대로 붙여서 시작하고, `[]`만 현재 상황에 맞게 바꾼다.

### 초급용 1줄 스타터 프롬프트

```text
Use $payment-mor-core to 설계해줘: Polar/Lemon 병행 결제를 위한 최소 MVP 백엔드 구조(create-order, webhook, confirm, idempotency)만 먼저.
```

```text
Use $payment-mor-core to 비교해줘: 우리 서비스([서비스명], [국가/상품유형]) 기준으로 Polar vs Lemon 우선순위 1개와 이유.
```

```text
Use $payment-mor-core to 만들어줘: 출처 태그 포함 운영 체크리스트(서명검증, 중복웹훅, paid 이후 지급, 모니터링 지표).
```

### 템플릿 1: 제로베이스 전체 구축

```text
Use $payment-mor-core.

목표: [서비스명]에 Polar + Lemon Squeezy 병행 지원 결제 모듈을 제로베이스로 구축한다.
요구사항:
1) provider-agnostic 도메인 상태 모델 정의
2) create-order / webhook / confirm API 계약 정의
3) raw body 서명검증과 event_id 멱등 처리 구현
4) paid 확정 이후 권한/크레딧 지급 처리
5) 테스트 시나리오(정상/서명오류/중복웹훅) 제시
6) 모든 정책/수치 판단 문장에 source-index 태그 인용

산출물은 체크리스트 + 코드 스켈레톤 + 운영 점검 항목으로 제시한다.
```

### 템플릿 2: 백엔드 결제 API 우선 구현

```text
Use $payment-mor-core.

현재 프론트는 나중에 붙이고, 백엔드 결제 API를 먼저 완성한다.
대상:
- `/api/payments/create-order`
- `/api/payments/webhook`
- `/api/payments/confirm`

요구사항:
1) Polar/Lemon 어댑터 인터페이스와 구현 골격 작성
2) 주문 생성 실패 시 상태 전이(failed) 일관성 보장
3) 웹훅 처리 순서 `verify -> parse -> dedupe -> transition -> provisioning` 강제
4) DB 멱등키 기준으로 이중 지급 방지
5) 출처 태그 포함 근거 제시
```

### 템플릿 3: 정책/비용 검토 + 기술안 제안

```text
Use $payment-mor-core.

상황: [국가/상품유형/요금제] 기준으로 Polar와 Lemon Squeezy 중 우선 공급자를 정해야 한다.
작업:
1) 수수료/정산주기/허용상품/국가지원 비교표 작성
2) 우리 서비스에 맞는 1순위/2순위와 이유 제시
3) 기술 적용안(어댑터/웹훅/원장) 제시
4) 변경 추적을 위해 source-index 태그와 링크를 함께 제공

결론은 '이번 배포 권장안 1개'로 명확하게 제시한다.
```

## 템플릿 입력 변수 가이드

아래 항목은 템플릿 실행 전에 먼저 채운다.

| 변수 | 필수 | 설명 | 예시 |
| --- | --- | --- | --- |
| `[서비스명]` | 필수 | 결제 모듈을 붙일 실제 서비스 이름 | `MomPick AI` |
| `[국가/상품유형/요금제]` | 필수 | 정책/수수료 비교에 필요한 판매 맥락 | `KR / 디지털 크레딧 / one-time` |
| `[권한/크레딧 지급 방식]` | 권장 | 결제 후 어떤 리소스를 활성화하는지 | `크레딧 +20 지급` |
| `[기술 스택]` | 권장 | 코드 예시를 맞춤 생성하기 위한 런타임 정보 | `Vercel + Supabase + TypeScript` |
| `[배포 목표일]` | 권장 | 범위 축소/우선순위 결정을 위한 일정 기준 | `2026-03-10` |

## 출력 형식 고정 (권장)

템플릿 실행 결과는 아래 순서를 기본으로 한다.

1. 목표/가정: 범위, 제외 범위, 의사결정 기준
2. 아키텍처: provider-agnostic 도메인 계약 + 공급자 어댑터 경계
3. API 계약: create-order / webhook / confirm 요청·응답 스키마
4. 웹훅 멱등 설계: 서명검증, event_id 중복방지, 상태전이 규칙
5. 테스트 매트릭스: 정상/서명오류/중복/역순 이벤트
6. 운영 체크리스트: 모니터링 지표, 장애 대응, 롤백 조건
7. 출처 태그 목록: 사용한 태그 + 원문 링크

## 템플릿 사용 금지사항

- source-index 태그 없는 정책/수치 단정 금지
- success redirect만으로 결제 성공 처리 금지
- 공급자 전용 이벤트명을 내부 도메인 상태로 직접 노출 금지
- 멱등키 없이 크레딧/권한 반영 금지
- 샌드박스 검증 없이 운영 전환 금지

## 표준 구현 흐름

### 1) 도메인 계약 먼저 고정

- 결제 상태를 먼저 고정한다: `created | pending | paid | failed | refunded | canceled`.
- 공급자별 이벤트명은 내부 표준 상태로 매핑한다.
- 내부 DB는 공급자 고유 페이로드를 별도 컬럼(JSON)로 보관하되, 비즈니스 판단은 내부 표준 필드로 처리한다.

권장 어댑터 인터페이스:

```ts
export interface MorPaymentAdapter {
  provider: "polar" | "lemonsqueezy";
  createCheckout(input: {
    internalOrderId: string;
    productCode: string;
    successUrl: string;
    metadata: Record<string, string>;
  }): Promise<{ checkoutUrl: string; externalCheckoutId?: string }>;
  verifyWebhook(rawBody: Buffer, headers: Record<string, string | string[] | undefined>): void;
  parseWebhook(rawBody: Buffer, headers: Record<string, string | string[] | undefined>): {
    eventId: string;
    eventType: string;
    externalOrderId?: string;
    normalizedStatus?: "pending" | "paid" | "failed" | "refunded" | "canceled";
    payload: unknown;
  };
}
```

### 2) 체크아웃 생성 API 구현

- 클라이언트는 `productCode`만 전달하고, 실제 가격/상품 식별자는 서버에서만 매핑한다.
- 서버에서 내부 주문을 먼저 생성한 뒤, 공급자 체크아웃 URL을 만든다.
- 체크아웃 URL 생성 실패 시 내부 주문 상태를 `failed`로 전이하고 원인 메시지를 보관한다.

### 3) 웹훅 검증/처리 API 구현

- `verify -> parse -> dedupe -> state transition -> side effect(크레딧 지급)` 순서를 지킨다.
- 상태 전이는 단방향으로 제한한다. 예: `paid` 이후 `pending`으로 되돌리지 않는다.
- 지연/재시도 가능성을 전제로, 같은 이벤트가 여러 번 와도 결과가 동일해야 한다.

Polar/Lemon 실전 체크(반드시 적용):

- Polar 멱등 키는 가능하면 `webhook-id`(전달 고유 ID)를 우선 사용한다.
- `payload.data.id`는 주문 ID로 재사용될 수 있어 `order.updated`와 `order.paid`가 충돌할 수 있다.
- Polar 서명 헤더는 환경마다 이름이 다를 수 있으니 `webhook-*`, `x-webhook-*`, `svix-*`를 모두 수용한다.
- Polar 대시보드의 `polar_whs_...` 시크릿은 base64로 디코딩하지 말고 raw 문자열 바이트로 HMAC 검증한다.
- 영구 오류(`order_not_found`, `amount_mismatch`)는 내부 기록 후 HTTP 200으로 ack 처리해 재전송 폭주를 막는다.

### 4) 결제 후 프로비저닝(권한/크레딧 지급)

- 웹훅에서 `paid` 확정 이후에만 지급한다.
- 지급 원장은 `entry_type=purchase`, `reference_id=internalOrderId`처럼 조회 가능한 키로 저장한다.
- 지급 실패 시 재처리를 위해 큐/재시도 테이블을 둔다.

### 5) 운영 안정화

- 샌드박스에서 최소 3가지 시나리오를 통과시킨다:
- 정상 결제
- 서명 불일치 웹훅
- 중복 웹훅(같은 event_id 2회)

## 출처 추적 규칙

- 정책/수치/제약을 문서에 쓸 때 반드시 출처 태그를 붙인다. 예: `[POLAR_MOR_FEES]`, `[LEMON_WEBHOOK_SIGNING]`.
- 신규 사실을 추가하면 `references/source-index.md`에 태그를 먼저 등록한다.
- 변경 대응 시 순서:
1. `scripts/verify_source_links.sh` 실행
2. 깨진 링크 또는 문구 변경 태그 확인
3. 해당 태그가 참조되는 문서/코드 주석/운영 문서를 같이 업데이트

## 리소스

- `references/source-index.md`: 공식 문서 태그 사전(단일 진실 원천)
- `references/polar.md`: Polar 적용 규칙/주의사항
- `references/lemonsqueezy.md`: Lemon Squeezy 적용 규칙/주의사항
- `references/integration-checklist.md`: 제로베이스 통합 절차
- `scripts/verify_source_links.sh`: 출처 링크 상태 점검
