---
name: git-push
description: >
  GitHub 계정 전환 후 push하는 스킬. 프로젝트별로 다른 GitHub 계정(개인/회사)을 사용할 때,
  author 정보와 SSH 인증을 자동으로 전환하고 push한다. Vercel 자동 배포가 실패할 때,
  커밋 author가 잘못되었을 때, 회사/개인 계정을 전환해야 할 때 사용한다.
  트리거: /git-push, 푸시해줘, GitHub 계정 전환, Vercel 배포 안됨
---

# Git Push with Profile Switching

프로젝트별 GitHub 계정(author + SSH 인증)을 자동 전환하고 push하는 스킬.

## 설정 파일

프로젝트 루트에 `.github-profile.json` 파일이 필요하다.

### Kyle의 프로필 (기본 템플릿)

기본 템플릿 파일은 스킬 내부에 포함되어 있다.

파일 위치: DEFAULT-GITHUB-PROFILE.kyle.json

### 자동 생성

`.github-profile.json`이 없으면 기본 템플릿을 프로젝트 루트에 자동 생성한다.
사용자가 "개인으로 푸쉬" 또는 "회사로 푸쉬"라고 말하면 해당 프로필로 activeProfile을 설정한다.
명시가 없으면 템플릿의 activeProfile 값을 그대로 사용한다.

## 사전 요구사항: SSH Config

`~/.ssh/config`에 계정별 Host를 설정해야 한다:

```
Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_personal

Host github-company
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_company
```

## 워크플로우

### 1. 설정 파일 확인

```bash
cat .github-profile.json
```

파일이 없으면 사용자에게 생성을 안내한다.

### 2. 프로필 적용

activeProfile 또는 사용자 지정 프로필로 git config 변경:

```bash
git config --local user.name "프로필의 name"
git config --local user.email "프로필의 email"
```

### 3. Remote URL 변경

현재 remote URL의 호스트를 프로필의 sshHost로 변경:

```bash
# 현재 remote 확인
git remote -v

# 예: git@github.com:user/repo.git → git@github-company:user/repo.git
git remote set-url origin git@{sshHost}:{user}/{repo}.git
```

### 4. Push 실행

```bash
git push origin {current-branch}
```

## 명령어 옵션

| 사용법 | 설명 |
|--------|------|
| `/git-push` | activeProfile로 push |
| `/git-push --profile company` | 지정 프로필로 push |
| `/git-push --set-default personal` | 기본 프로필 변경 후 push |
| `/git-push --amend` | 마지막 커밋 author 수정 후 push |

## 자연어 사용 규칙

다음 문구가 포함되면 해당 프로필로 push를 수행한다.

- "개인으로 푸쉬", "개인 계정으로 푸쉬", "개인으로 푸시해줘"
- "회사로 푸쉬", "회사 계정으로 푸쉬", "회사로 푸시해줘"

이 경우 activeProfile도 해당 값으로 갱신한다.
명시가 없으면 activeProfile을 그대로 사용한다.

## --amend 옵션

마지막 커밋의 author를 현재 프로필로 변경:

```bash
git commit --amend --author="name <email>" --no-edit
```

주의: 이미 push된 커밋은 force push 필요. 사용자에게 확인 후 진행.

## 에러 처리

| 상황 | 대응 |
|------|------|
| .github-profile.json 없음 | **자동으로 Kyle 템플릿 생성** (activeProfile만 물어봄) |
| SSH 키 없음 | ssh-keygen 명령어 안내 |
| Remote 없음 | git remote add 안내 |
| Push 권한 없음 | SSH 키가 GitHub에 등록되었는지 확인 안내 |

## 새 프로젝트 초기화 워크플로우

Git이 초기화되지 않은 새 프로젝트의 경우:

```bash
# 1. Git 초기화
git init

# 2. .github-profile.json 생성 (위 템플릿 사용)
# activeProfile을 사용자에게 확인: "personal" 또는 "company"?

# 3. .gitignore에 추가 (선택사항 - 프로필 공개 원치 않으면)
# echo ".github-profile.json" >> .gitignore

# 4. Git config 설정
git config --local user.name "{profile.name}"
git config --local user.email "{profile.email}"

# 5. 첫 커밋
git add .
git commit -m "Initial commit"

# 6. GitHub repo 생성 (gh CLI 사용)
gh repo create {repo-name} --private --source=. --remote=origin

# 7. Remote URL을 sshHost로 변경
git remote set-url origin git@{sshHost}:{username}/{repo-name}.git

# 8. Push
git push -u origin main
```
