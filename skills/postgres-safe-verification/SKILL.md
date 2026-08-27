---
name: postgres-safe-verification
description: Verify PostgreSQL-specific behavior safely without inserting dummy data into dev or production. Use for SQL semantics such as BTRIM/TRIM, Unicode whitespace, JSONB, arrays, NULL handling, CTEs, constraints, date/time behavior, candidate inclusion/exclusion, or when deciding between PGlite, Docker, a local PostgreSQL server, and read-only remote checks.
metadata:
  short-description: Safely verify PostgreSQL behavior with an evidence ladder
---

# PostgreSQL Safe Verification

## Why

실제 dev·운영 데이터를 더미 데이터로 오염시키지 않으면서 PostgreSQL 고유 동작을 재현 가능하게 검증한다.

## Trust model

PGlite는 PostgreSQL을 WebAssembly로 빌드한 실제 PostgreSQL 계열 엔진이다. 공식 문서가 단위 테스트와 CI를 대표 사용 사례로 안내하므로 순수 SQL 의미 검증에는 신뢰할 수 있다.

다만 PGlite는 단일 사용자·단일 연결 구조이며 네이티브 서버와 운영 환경 전체를 재현하지 않는다. 다음 항목의 최종 증거로 사용하지 않는다.

- 실제 인덱스 선택과 대규모 성능
- 동시성, 잠금, 데드락, 연결 풀
- RDS 설정과 버전 차이
- 로케일, collation, ICU 차이
- 네이티브 확장 기능
- 마이그레이션 전체 실행
- 네트워크, SSL, 인증, 권한

공식 근거:

- PGlite 소개와 Unit/CI testing 용도: https://pglite.dev/docs/about
- PGlite 문서: https://pglite.dev/docs/
- 구현과 제한: https://github.com/electric-sql/pglite

## Verification ladder

필요한 증거까지만 단계적으로 높인다. Docker부터 시작하지 않는다.

### 1. 애플리케이션 단위 테스트

다음을 먼저 확인한다.

- 애플리케이션이 올바른 SQL과 파라미터를 만드는가
- 실제 제품 코드의 상수와 정규화 함수를 사용하는가
- 정상값, 경계값, 제외값이 모두 있는가
- 변경 범위 밖 조회에는 새 동작이 번지지 않는가

Mock 테스트는 SQL 구성 검증에는 유용하지만 PostgreSQL 실행 결과의 증거는 아니다.

### 2. 로컬 PGlite 의미 검증

다음처럼 PostgreSQL 함수 자체의 결과가 핵심이면 PGlite를 우선 사용한다.

- `TRIM`, `BTRIM`, 특수 공백
- `JSONB`, 배열, `NULL`
- CTE, 집계, 조건식
- 날짜와 시간대 연산
- 단순 CHECK·UNIQUE 동작
- 후보 포함·제외 규칙

기본 방식:

1. 제품 저장소에 의존성을 바로 추가하지 않는다.
2. `/tmp/<project>-postgres-verification` 같은 별도 폴더에 PGlite를 설치한다.
3. 제품 코드의 상수와 SQL 조각을 가능하면 직접 import한다.
4. SQL에는 `VALUES` fixture와 파라미터 바인딩을 사용한다.
5. 포함되어야 할 행과 제외되어야 할 행을 함께 assert한다.
6. DB를 닫고 실행 결과를 기록한다.
7. 임시 파일은 자동 삭제하지 않는다. 경로를 보고하고 필요 시 `.staging/` 원칙을 따른다.

예시 뼈대:

```js
import assert from 'node:assert/strict'
import { PGlite } from '@electric-sql/pglite'

const db = new PGlite()
const result = await db.query(
  `WITH fixtures(id, value) AS (
     VALUES (1, $1), (2, $2), (3, $3)
   )
   SELECT id
   FROM fixtures
   WHERE BTRIM(value, $4) = $5
   ORDER BY id`,
  [leadingValue, trailingValue, unrelatedValue, edgeCharacters, expectedValue],
)

assert.deepEqual(result.rows.map(({ id }) => Number(id)), expectedIds)
await db.close()
```

Fixture 최소 구성:

- 정상 기준값
- 앞 공백 또는 앞 경계문자
- 뒤 공백 또는 뒤 경계문자
- 문자열 중간의 보존 대상 문자
- 완전히 다른 값
- 삭제·다른 소유자·다른 분류처럼 업무 조건에서 제외될 값

### 3. 실제 스키마 읽기 전용 확인

실제 테이블·조인·컬럼·타입 호환성이 중요하면 dev 또는 운영의 읽기 전용 연결에서 다음만 사용한다.

- `SELECT`
- `VALUES`
- 일반 `EXPLAIN`
- `information_schema` 조회

금지 기본값:

- `INSERT`, `UPDATE`, `DELETE`
- DDL
- 임시 테이블
- `EXPLAIN ANALYZE`
- 운영 데이터 원문 출력

원격 DB 접근 전에는 프로젝트별 접속·승인·터널 규칙을 먼저 읽는다.

### 4. 네이티브 PostgreSQL 통합 검증

다음 중 하나라도 해당하면 PGlite에서 끝내지 않고 Docker, 로컬 PostgreSQL, 또는 격리된 테스트 DB를 사용한다.

- 실제 마이그레이션 적용
- 여러 테이블 관계와 ORM 전체 실행
- 네이티브 확장 기능
- 인덱스와 실행 계획 성능
- 트랜잭션 격리와 동시성
- 잠금과 데드락
- 운영 버전·설정 재현

Docker는 목적이 아니라 격리된 네이티브 PostgreSQL이 필요할 때 쓰는 수단이다.

### 5. dev 사용자 흐름 QA

저장·조회·화면 연결처럼 사용자가 보는 흐름은 dev에서 별도로 확인한다. SQL 의미 테스트가 dev QA를 대체하지 않는다.

## Decision guide

| 확인 질문 | 최소 권장 증거 |
| --- | --- |
| 애플리케이션이 올바른 조건을 만드는가 | 단위 테스트 |
| PostgreSQL 함수가 경계값을 어떻게 처리하는가 | PGlite `VALUES` 테스트 |
| 실제 스키마에서 SQL이 성립하는가 | 읽기 전용 `EXPLAIN` |
| ORM과 관계 테이블 전체가 작동하는가 | 격리된 네이티브 PostgreSQL |
| 인덱스·성능·잠금이 안전한가 | 네이티브 PostgreSQL과 실제 크기 데이터 |
| 사용자가 보는 흐름이 정상인가 | dev QA |

## Completion criteria

완료 보고에는 다음을 구분해서 적는다.

- 사용한 엔진과 버전 또는 방식
- 실제 제품 코드에서 재사용한 상수·SQL
- 포함된 fixture와 제외된 fixture
- 예상 결과와 실제 결과
- 실행한 단위 테스트와 빌드
- 원격 DB 또는 인프라 변경 여부
- PGlite로 확인하지 못한 남은 범위
- 임시 검증 파일 경로

PGlite 결과를 네이티브 PostgreSQL 전체 통합 테스트나 운영 성능 검증으로 과장하지 않는다.
