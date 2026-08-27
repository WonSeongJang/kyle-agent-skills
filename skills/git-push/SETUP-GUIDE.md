# git-push 스킬 설치 가이드

GitHub 계정 전환 후 push하는 Claude Code 스킬입니다.
프로젝트별로 다른 GitHub 계정(개인/회사)을 사용할 때 유용합니다.

---

## 1. 스킬 파일 설치

```bash
# 폴더 생성
mkdir -p ~/.claude/skills/git-push

# SKILL.md 파일 복사
cp SKILL.md ~/.claude/skills/git-push/
```

---

## 2. SSH 키 설정

### 2-1. SSH 키 생성

계정별로 각각 생성합니다.

```bash
# 개인용 키
ssh-keygen -t ed25519 -C "personal@email.com" -f ~/.ssh/id_personal

# 회사용 키 (필요시)
ssh-keygen -t ed25519 -C "work@company.com" -f ~/.ssh/id_company
```

### 2-2. SSH Config 설정

```bash
vi ~/.ssh/config
```

다음 내용을 추가합니다:

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

### 2-3. GitHub에 공개키 등록

```bash
# 공개키 내용 복사
cat ~/.ssh/id_personal.pub
```

1. GitHub 접속 → Settings → SSH and GPG keys
2. "New SSH Key" 클릭
3. 복사한 공개키 붙여넣기
4. 회사 계정도 동일하게 진행

### 2-4. SSH 연결 테스트

```bash
ssh -T git@github-personal
ssh -T git@github-company
```

`Hi {username}! You've successfully authenticated...` 메시지가 나오면 성공.

---

## 3. 프로젝트별 설정 파일

각 프로젝트 루트에 `.github-profile.json` 파일을 생성합니다.

스킬에는 기본 템플릿 파일이 포함되어 있으며, 파일이 없으면 자동 생성합니다.
기본 템플릿 파일 이름은 DEFAULT-GITHUB-PROFILE.kyle.json 입니다.

```json
{
  "activeProfile": "personal",
  "profiles": {
    "personal": {
      "name": "YourGitHubUsername",
      "email": "your@email.com",
      "sshHost": "github-personal"
    },
    "company": {
      "name": "CompanyUsername",
      "email": "work@company.com",
      "sshHost": "github-company"
    }
  }
}
```

| 필드 | 설명 |
|------|------|
| `activeProfile` | 기본으로 사용할 프로필 이름 |
| `name` | Git commit author 이름 |
| `email` | Git commit author 이메일 |
| `sshHost` | SSH config의 Host 이름 |

---

## 4. 사용법

Claude Code에서 다음 명령어를 사용합니다:

| 명령어 | 설명 |
|--------|------|
| `/git-push` | activeProfile로 push |
| `/git-push --profile company` | 지정 프로필로 push |
| `/git-push --set-default personal` | 기본 프로필 변경 후 push |
| `/git-push --amend` | 마지막 커밋 author 수정 후 push |

자연어로도 실행할 수 있습니다.

- 개인으로 푸쉬, 개인 계정으로 푸쉬, 개인으로 푸시해줘
- 회사로 푸쉬, 회사 계정으로 푸쉬, 회사로 푸시해줘

해당 문구가 포함되면 activeProfile도 함께 갱신합니다.

---

## 5. 설치 체크리스트

- [ ] `SKILL.md` 파일을 `~/.claude/skills/git-push/`에 복사
- [ ] SSH 키 생성 완료
- [ ] `~/.ssh/config` 설정 완료
- [ ] GitHub에 공개키 등록 완료
- [ ] SSH 연결 테스트 성공
- [ ] 프로젝트에 `.github-profile.json` 생성

---

## 6. 문제 해결

| 문제 | 해결 방법 |
|------|-----------|
| `Permission denied (publickey)` | SSH 키가 GitHub에 등록되었는지 확인 |
| `.github-profile.json not found` | 프로젝트 루트에 파일 생성 |
| `Host key verification failed` | `ssh-keyscan github.com >> ~/.ssh/known_hosts` 실행 |
| 프로필 전환이 안됨 | `~/.ssh/config` 파일 권한 확인 (`chmod 600`) |
