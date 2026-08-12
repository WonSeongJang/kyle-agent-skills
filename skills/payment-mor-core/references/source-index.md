# Payment MoR Core Sources

기준일: 2026-02-26 (America/Los_Angeles 세션 기준)

운영 규칙:

- 정책/수치/제약 문장은 반드시 아래 태그를 인용한다.
- 새 출처를 추가할 때는 먼저 이 문서에 태그를 등록한다.
- 링크 유효성은 `bash scripts/verify_source_links.sh`로 점검한다.

## Source Table

| Tag | Provider | Topic | URL | Last Checked |
| --- | --- | --- | --- | --- |
| `POLAR_MOR_FEES` | Polar | MoR 수수료 | https://polar.sh/docs/merchant-of-record/fees | 2026-02-26 |
| `POLAR_SUPPORTED_COUNTRIES` | Polar | 판매/정산 가능 국가 | https://polar.sh/docs/merchant-of-record/supported-countries | 2026-02-26 |
| `POLAR_ACCEPTABLE_USE` | Polar | 허용/금지 비즈니스 | https://polar.sh/docs/merchant-of-record/acceptable-use | 2026-02-26 |
| `POLAR_CHECKOUT_OVERVIEW` | Polar | 체크아웃 통합 개요 | https://polar.sh/docs/features/checkout | 2026-02-26 |
| `POLAR_CHECKOUT_SESSION` | Polar | 체크아웃 세션 생성 가이드 | https://polar.sh/docs/features/checkout/session | 2026-02-26 |
| `POLAR_CREATE_CHECKOUT_API` | Polar | Checkout API (create session) | https://docs.polar.sh/api-reference/checkouts/create-session | 2026-02-26 |
| `POLAR_WEBHOOK_ENDPOINTS` | Polar | 웹훅 엔드포인트 생성/관리 | https://polar.sh/docs/integrate/webhooks/endpoints | 2026-02-26 |
| `POLAR_WEBHOOK_DELIVERY` | Polar | 웹훅 재시도/전송 정책 | https://polar.sh/docs/integrate/webhooks/delivery | 2026-02-26 |
| `POLAR_WEBHOOK_SIGNATURE` | Polar | 서명 검증(standardwebhooks) | https://docs.polar.sh/integrate/webhooks | 2026-02-26 |
| `POLAR_API_CHANGELOG` | Polar | API 변경 이력 | https://docs.polar.sh/changelog/api | 2026-02-26 |
| `LEMON_MOR` | Lemon Squeezy | Merchant of Record 정의 | https://docs.lemonsqueezy.com/help/payments/merchant-of-record | 2026-02-26 |
| `LEMON_CREATE_CHECKOUT` | Lemon Squeezy | Checkout 생성 API | https://docs.lemonsqueezy.com/api/checkouts/create-checkout | 2026-02-26 |
| `LEMON_WEBHOOK_SIGNING` | Lemon Squeezy | 웹훅 서명 검증 | https://docs.lemonsqueezy.com/help/webhooks/signing-requests | 2026-02-26 |
| `LEMON_WEBHOOK_REQUESTS` | Lemon Squeezy | 웹훅 재시도 정책 | https://docs.lemonsqueezy.com/help/webhooks/webhook-requests | 2026-02-26 |
| `LEMON_FEES` | Lemon Squeezy | 플랫폼/추가 수수료 | https://docs.lemonsqueezy.com/help/getting-started/fees | 2026-02-26 |
| `LEMON_GETTING_PAID` | Lemon Squeezy | 정산 주기/홀드 | https://docs.lemonsqueezy.com/help/getting-started/getting-paid | 2026-02-26 |
| `LEMON_SUPPORTED_COUNTRIES` | Lemon Squeezy | 판매/정산 가능 국가 | https://docs.lemonsqueezy.com/help/getting-started/supported-countries | 2026-02-26 |
| `LEMON_PROHIBITED_PRODUCTS` | Lemon Squeezy | 금지 상품/서비스 | https://docs.lemonsqueezy.com/help/getting-started/prohibited-products | 2026-02-26 |

## 빠른 재검증 절차

1. `bash scripts/verify_source_links.sh`
2. 4xx/5xx 링크가 있으면 문서 경로 변경 여부를 확인한다.
3. 태그를 참조하는 파일(`references/*.md`, `SKILL.md`, 구현 코드 주석)을 함께 업데이트한다.
