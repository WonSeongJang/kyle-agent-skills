---
name: nanobanana2-image-gen
description: >
  Kyle이 명시적으로 나노바나나/Gemini/Ultra 계정을 지정했을 때만 사용하는 이미지 생성 스킬.
  일반 이미지 생성 요청에는 사용하지 않는다.
  트리거: 나노바나나로, Gemini로, Ultra 계정으로, nanobanana
---

# Nano Banana 2 이미지 생성 스킬

이 스킬은 `[kyle]`가 명시적으로 나노바나나 계열 모델 사용을 요청했을 때만 사용한다.
일반적인 `이미지 만들어줘` 요청에는 Codex 내장 이미지 생성을 기본값으로 둔다.

Gemini 3.1 Flash Image Preview 모델을 사용해 이미지를 생성한다.

## 계정 정보

### 기본값: Ultra 계정

| 항목 | 값 |
|------|-----|
| 시크릿 경로 | `~/.kyle-secrets/gcp/image-workloads/nanobanana2-sngm20801-ultra.env` |
| 환경변수 키 | `API_KEY` |
| GCP Account | sngm20801@gmail.com (AI Ultra) |
| GCP Project | applied-plexus-491202-d6 |
| 크레딧 | $100/월 (AI Studio + Vertex AI + GCP) |

### 보조: Pro 계정 (Ultra 크레딧 부족 시)

| 항목 | 값 |
|------|-----|
| 시크릿 경로 | `~/.kyle-secrets/gcp/image-workloads/nanobanana2-securenet2080.env` |
| 환경변수 키 | `API_KEY` |
| GCP Account | securenet2080@gmail.com (AI Pro) |

Kyle이 별도 지정 없으면 Ultra 계정을 사용한다.

추가 메모:

- 현재 `gcp/` canonical 구조는 `accounts/ + projects/ + image-workloads/` 다.
- 예전 flat 파일 `~/.kyle-secrets/gcp/nanobanana2-ultra.env`, `~/.kyle-secrets/gcp/nanobanana2.env` 는 staging 으로 이동됐다.
- 따라서 새 이미지 생성 스크립트나 수동 호출 예시는 `image-workloads/` 아래 canonical 파일을 기준으로 본다.

## 모델 정보

- **모델명**: `gemini-3.1-flash-image-preview`
- **REST endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent`
- **공식 문서**: `/Users/fw_m1/Dev/vive-md-upstream/나노바나나2docs.md`

## API 호출 패턴 (Node.js REST)

```javascript
const API_KEY = /* env 파일에서 읽기 */;
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent`;

const body = {
  contents: [{ parts: [{ text: prompt }] }],
  generationConfig: {
    responseModalities: ["TEXT", "IMAGE"],
    imageConfig: {
      aspectRatio: "3:2",  // 아래 옵션 참고
      imageSize: "1K",     // 아래 옵션 참고
    },
  },
};

const res = await fetch(`${ENDPOINT}?key=${API_KEY}`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

const data = await res.json();
for (const part of data.candidates[0].content.parts) {
  if (part.inlineData) {
    const buffer = Buffer.from(part.inlineData.data, "base64");
    fs.writeFileSync("output.png", buffer);
  }
}
```

## 설정 옵션

### 종횡비 (aspectRatio)

`1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`

### 해상도 (imageSize)

`512`, `1K`, `2K`, `4K`

### 용도별 기본값

| 용도 | 종횡비 | 해상도 |
|------|--------|--------|
| 랜딩/히어로 이미지 | 3:2 | 2K |
| 앱 feature 이미지 | 3:2 | 2K |
| 카드 배경 | 3:2 | 1K |
| 앱 스텝/How 이미지 | 3:2 | 1K |
| 아이콘/Empty State | 1:1 | 1K |
| 로딩/에러 소형 아이콘 | 1:1 | 512 |
| OG 이미지 | 16:9 | 2K |
| 모바일 전용 | 9:16 | 1K |

## 프롬프트 전략

### 일러스트/아이콘

```
Minimal flat illustration style, soft pastel colors with [accent color] as accent,
clean vector art, white/transparent background feel, friendly and warm tone,
no text, no words, no letters. [구체적 묘사]
```

### 앱 UI 목업

```
A clean, modern mobile app UI mockup showing [화면 설명].
Clean white background with [accent color]. Rounded input fields,
modern Material Design inspired. The phone is shown at a slight angle
with subtle shadow. [추가 묘사]
```

### 수채화/배경

```
Soft watercolor-style illustration of [장면 묘사],
very light and translucent, meant to be used as a card background
overlay at 15% opacity. [색상] pastel tones, no text, no people,
atmospheric and dreamy.
```

### 사실적 사진

```
A photorealistic [shot type] of [subject], [action or expression],
set in [environment]. Illuminated by [lighting], creating a [mood]
atmosphere. Captured with [camera/lens]. [aspect ratio] format.
```

## 생성 스크립트 작성 규칙

1. **위치**: 프로젝트 `public/images/` 또는 해당 이미지 디렉토리에 `generate-*.mjs`로 생성
2. **API 키 로드**: env 파일에서 읽기 (하드코딩 금지)
3. **순차 실행**: 요청 간 2초 딜레이 (rate limit 방지)
4. **에러 핸들링**: 500 에러 시 1회 재시도
5. **결과 출력**: 파일명, 크기(KB) 로그
6. **생성 후**: 이미지를 Read 도구로 시각 확인

## 참고

- 모든 생성 이미지에 SynthID 워터마크 포함
- Thinking 모드 사용 가능 (복잡한 프롬프트 시 `thinkingConfig` 추가)
- 참조 이미지 최대 14개 업로드 가능 (text-and-image-to-image)
- 상세 API 문서: `/Users/fw_m1/Dev/vive-md-upstream/나노바나나2docs.md`
