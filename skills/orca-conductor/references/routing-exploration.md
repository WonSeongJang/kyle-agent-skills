# 제한적 실제 탐색 라우팅

## Why

기존 최고점 모델만 계속 써서 다른 모델의 실제 성과 표본이 영원히 쌓이지 않는 문제를, 안전한 작업의 작은 비율에서만 해결한다.

## 기본 계약

- `--exploration-share-percent` 기본값은 `0`이다. 옵션을 주지 않으면 기존 라우팅 결과가 그대로다.
- 허용 범위는 `0..10`이다.
- 이 0~10%는 새 `taskClassPrior` 재선택기의 예산이다. 기존 기본 라우터의 provider별 실험 자격(현재 Opus `experimentSharePercent: 20`)과는 별도이며, 둘을 합친 전역 실험 상한을 뜻하지 않는다. 원장에서는 기본 라우터의 `experiment_share` 이유와 새 `exploration.share_percent`를 분리해 집계한다.
- 같은 `--experiment-key`와 `taskClass`는 항상 같은 0~99 칸을 받는다.
- 탐색을 켤 때 프로젝트 감독은 카드 내용을 확인한 뒤 `--risk-assessment-complete`를 반드시 붙인다. 빠지면 탐색은 꺼진다.
- 위험 표식이 하나라도 있으면 탐색하지 않는다.
- `docs_config`, `research`, `qa`는 LIGHT/HEAVY 모두 허용한다.
- `targeted_implementation`, `frontend`, `bugfix`는 LIGHT만 허용한다.
- `architecture`, `security`, `concurrency`, `other`는 탐색하지 않는다.
- 기존 선택 점수에서 15점 이내이며 `last_resort`가 아닌 대체 조합만 후보가 된다.
- 후보는 기존 점수에 `taskClassPrior`를 더해 정렬하고, 상위 3개 안에서 카드 키로 결정적으로 분산한다.

이 단계는 자동 학습기가 아니다. `taskClassPrior`는 아직 수동 가설이고, 실제 발령·검수·체크포인트 표본이 충분히 쌓인 뒤에만 조정한다.

이 플래그들은 보안 경계가 아니라 신뢰된 Orca 프로젝트 감독의 운영 입력이다. 신뢰되지 않은 사용자가 wrapper를 실행할 수 있는 환경에서는 탐색 비율을 0으로 유지한다. 감독이 카드의 실제 내용과 위험 표식을 대조하지 않았다면 `--risk-assessment-complete`를 붙이지 않는다.

## 사용 예

```bash
skills/orca-conductor/scripts/select-routing-pair.sh \
  --task-size light \
  --task-class frontend \
  --experiment-key '[판]:카드' \
  --risk-assessment-complete \
  --exploration-share-percent 10
```

위험한 문맥은 반복 가능한 `--risk-flag`로 명시한다.

```bash
skills/orca-conductor/scripts/select-routing-pair.sh \
  --task-size light \
  --task-class frontend \
  --risk-flag user_visible \
  --experiment-key '[판]:카드' \
  --risk-assessment-complete \
  --exploration-share-percent 10
```

두 번째 예시는 10% 칸에 들어가도 실제 선택을 바꾸지 않는다.

## 기록 해석

stdout의 `exploration`은 원래 조합(`base`), 실제 조합(`chosen`), 하네스, 칸 번호, 이유를 보여준다. 자동 원장의 `payload.exploration`에도 같은 값이 남고, `payload.shadow`는 별도의 성격 점수 비교를 계속 보존한다.
